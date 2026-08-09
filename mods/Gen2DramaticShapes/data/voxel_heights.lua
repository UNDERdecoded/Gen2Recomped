-- Voxel world mode: the shape PROFILE -- hand-authored pins over the
-- automatic structure detector, the way a 3dSen game profile pins a
-- graphic to a geometry type.
--
-- Hand-authored by this mod, and read only from here: unlike the tables the
-- ROM extractor writes into the player's own cache, nothing below is
-- extracted, derived or copied from the ROM.
-- Nothing here reaches gameplay, collision or scripts; an entry can only
-- ever change how a tile LOOKS in voxel mode.
--
-- Most of the world needs no entry. The runtime detects structures on its
-- own (src/render/voxel/Structures.lua): it flood-fills each connected
-- drawn thing, voxelizes small props per pixel at their real drawn height
-- with transparency (a 2-row plant is a 16px-tall silhouette, not a box),
-- and raises everything else as a volume whose height is measured from the
-- drawing itself -- repeat-aware, so a 6-row house is 48px while a 40-row
-- border forest is rows of 16px trees, not a monolith.
--
-- Listing a tile here BYPASSES that detection: the tile takes the class's
-- height and art mode, always. Use it where the detector reads art wrong,
-- or from a mod to pin its own tiles. Resolution order per tile:
--
--   1. a group listed under tilesets[<id>] below        (this profile)
--   2. the tile sits in a water cell                    -> "water"
--   3. the tile sits in a WALKABLE cell                 -> "ground"
--   4. tile-level fallback: the map's water set -> "water", its walkable
--      list -> "ground", anything left over             -> "wall"
--
-- Rules 2-3 work at CELL granularity (16x16, the walk grid) because that
-- is the granularity collision actually has: the engine judges a cell by
-- its bottom-left tile alone, so the other three tiles of a cell carry no
-- collision meaning -- flowers and grass tufts sit in walkable cells and
-- must stay flat ground even though no walkable list names them.
--
-- Classes (heights in world pixels; a map cell is 16x16):
--   ground / water / void   flat; water recesses so shorelines show a lip
--   ledge / roof / bed      box with the art on its TOP face; partial side
--                           faces crop the art (a 6px ledge face is the
--                           bottom of the lip drawing; a bed is its
--                           mattress drawn from above, lying low)
--   wall / tree / fence / sign / counter / table / desk
--                           box whose SOUTH face folds the 2D artwork
--                           upright, 8px band by band; authored boxes fold
--                           every face and wear their top row's art on top.
--                           A counter is half a cell -- one band, so its
--                           drawn front panel stands and its top stays on top
--   stair_e / stair_w       real steps rising toward the named side, the
--                           full cell deep, treads and slices textured
--                           from the drawn staircase
--   stair_down_e / _down_w  a sunken stairwell: the cell opens into a
--                           hole with steps descending toward the named
--                           side -- stairs that lead DOWN a floor
--   relief                  a prop drawn from above (a console on the
--                           floor): the drawing stays flat and the
--                           pixels inside its black outline extrude a
--                           few voxels, art on top
--   bookcase                a free-standing shelf drawn tall: each rank
--                           collapses onto a one-cell-deep box at its
--                           full drawn height; back rows become hidden
--                           floor, and an unpinnable trim row above
--                           becomes the cap.  Its FRONT carries the
--                           measured pane relief -- every non-black
--                           region the drawing seals behind its own
--                           black frame sinks one voxel, the same rule
--                           lib/Buildings.lua recesses a facade with,
--                           so the books stand in the shelf instead of
--                           being painted on it.  A tileset that
--                           borrows the collapse for something that is
--                           not a shelf says `bookcase_relief = false`
--   cylinder / canopy       round scenery (tree canopies): a voxel hull
--   / stump                 cut from the art's own darkest-pixel outline,
--                           round in depth -- one 16px cell, a 2x2-cell
--                           group, or with the drawn top read as a cut face
--   can                     that hull cut at both ends, hollowed and
--                           tapered: an OPEN bin standing on a floor
--                           (Vermilion Gym's trash cans).  The drawn mouth
--                           ellipse projects across the round top and down
--                           the well, the drawn base ellipse is ground
--                           contact rather than body, the top rows keep a
--                           wall at each end of their chord and lose the
--                           middle, and the plan narrows toward the floor
--                           (can_cap / can_base in art rows; can_height,
--                           can_well, can_taper in voxels)
--   planter                 the same hull for a round drawing stacked TWO
--                           cells high on ONE cell of plot (the Centers'
--                           potted plants): it stands in the lower cell and
--                           the upper cell is the height it overhangs
--   billboard / prop        a prop drawn face-on: a standing per-pixel
--                           cutout, black-outline segmented; drawn above
--                           a pinned box it stands ON that box (a
--                           monitor on its desk).  prop is a second pool
--                           so two touching cutouts stay separate
--   bike                    the same cutout at TWO voxels: a vehicle drawn
--                           side-on is a LINE drawing, and the air inside
--                           its frame is what makes it read as one -- any
--                           thicker and neighbouring strokes close those
--                           gaps with their own side faces
--
-- A tileset entry may also carry `prop_ground` (not a class): a map of
-- prop tile id -> ground tile id naming the tile painted under that
-- pinned prop, overriding the flat-neighbour vote -- the cuttable bush
-- stands on the grass Cut leaves behind, whatever borders it.
--
-- And `prop_bg` (not a class either): which GB shades count as BACKGROUND
-- when a pinned per-pixel prop is cut out, for the drawings whose own body
-- reaches the edge of their bounding box and so vote themselves away.
-- Keyed by tile, because two props sharing an atlas can want opposite
-- answers on the same shade.
--
-- And it may carry `figures` (not a class either): hand-drawn pixel masks
-- that lift a FIGURE PAINTED INTO furniture off it and stand it up as a
-- standee, leaving the furniture its own geometry.  A pin resolves a
-- whole 8x8 tile, so it can never separate two things that share one --
-- and nothing automatic can either when the figure has no background
-- margin to flood from and wears the same shades as what it sits on.
-- The Pokemon Center's seated man is the case; see POKECENTER below for
-- the format.  A figure entry that states a `depth` is not a person and
-- stands as a per-pixel SOLID instead of a flat card -- the Marts' cash
-- register, a machine set down on a counter (`thin` gives its top rows a
-- thickness of their own, for the part of a drawing that is paper).
--
-- And `mounted` (not a class either): the same authored-mask escape for a
-- thing painted INTO a WALL band, stood proud of the panel as a thin
-- per-pixel slab instead of standing on its feet as a sprite card.  Where
-- a figure is a person and reads face-on from any angle, a mounted object
-- is an object drawn side-on and holds the wall's own plane; and it keeps
-- its DRAWN elevation, so a thing hung clear of the floor stays hung.
-- The Bike Shop's two wall bicycles are the case -- and the mask there is
-- measured rather than drawn, by flooding the panel tile's own stripe out
-- from behind them; see CLUB below.
--
-- Whole BUILDINGS are not tile pins -- one drawing packs a roof seen from
-- above, a facade seen face-on and sloped ends as diagonal silhouettes,
-- and no single class covers that.  They live in the `buildings` list at
-- the bottom of this file, as a band table over the drawing's rows.

local profile = {
  version = 1,

  -- class -> height in world pixels
  heights = {
    ground = 0,
    water = -2,
    void = 0,
    ledge = 6,
    fence = 10,
    sign = 12,
    wall = 16,
    -- masonry drawn two courses tall (the Indigo Plateau's rim, the
    -- badge-check gates): as tall as a statue on its plinth
    cliff = 32,
    -- the top of a plateau: one course, so it lands flush with the 16px
    -- cliff face drawn holding it up
    terrace = 16,
    tree = 16,
    roof = 28,
    bed = 7,
    stool = 8,
    counter = 8,
    -- the raised back band of low seating (the Center couch's back and
    -- arm strip): half again the 8px seat it rises over
    backrest = 12,
    table = 12,
    desk = 24,
    prop = 16,
    cutout = 16,
    -- a vehicle drawn side-on (the Bike Shop's bicycles): a standee like
    -- the pools above, two voxels thin so the air inside its frame stays
    -- air (see Structures' PINNED_DEPTH)
    bike = 16,
    -- a round drawing stacked two cells high on one cell of plot (the
    -- Centers' potted plants): 32px of hull standing in its lower cell
    planter = 32,
    relief = 3,
    bookcase = 32,
    stair_e = 16,
    stair_w = 16,
    stair_down_e = 16,
    stair_down_w = 16,
  },

  -- Gen 2 collision class -> class, for every Gen 2 tileset at once.
  --
  -- Where Gen 1 hands the mesher a tile id and nothing else, Gen 2 stores a
  -- collision class per 16x16 CELL, and the classes are semantic: the ROM
  -- itself distinguishes a tree from a wall.  That reaches drawings a
  -- tile-id pin cannot -- Johto's lone tree and its tree WALL are cut from
  -- the same six tiles ($1E/$1F/$2E/$2F/$3E/$3F) and differ only in class --
  -- and one table covers all thirty tilesets instead of thirty pin lists.
  --
  -- Deliberately short.  Every row below is either read off the routine that
  -- consumes the class or confirmed against the metatile art; the many
  -- classes whose meaning is only guessable from their distribution are left
  -- to the detector, which is what rule 1 means by hand-authored.
  collision = {
    -- $15 is a tree standing alone on grass (Johto blocks $3C-$3F, $5B-$67),
    -- $12 the berry tree in the same drawings' corners, $7B the low round
    -- bush tucked against a cliff base (Johto block $73).  All three are
    -- drawn ROUND, so all three take the voxel-hull archetype; the tree
    -- WALL, class $07, is rounded by tile instead -- see TilesetJohto's
    -- `planter`, which is the only reading that gets its two-cell height
    [0x12] = "cylinder",
    [0x15] = "cylinder",
    [0x7B] = "cylinder",
    -- CheckGrassCollision's own list, minus the classes the permission table
    -- calls water: standing tufts the player walks between, not flat ground
    [0x18] = "grass",
    -- COLL_WATERFALL.  A fall is drawn as a band of $40 laid across the
    -- river -- eight blocks wide and two deep at Mt. Mortar, and the same
    -- shape at Tohjo Falls, Whirl Island B2F and Silver Cave -- and the
    -- band's cells are the only thing that separates it from the pool it
    -- pours into.  Unpinned it takes the water class and the whole river
    -- comes out one flat sheet with a texture change in the middle: no
    -- fall at all.  `cliff` is the upright fold, so the band stands up
    -- two courses and the falling water is drawn on its FACE, which is
    -- the direction it falls.  The rock flanking it is $26/$27 and takes
    -- the same class from the cave profile, so the gorge walls match.
    [0x33] = "cliff",
    -- Hop classes ($A0-$AF) are deliberately NOT pinned.  DoPlayerMovement
    -- reads the direction out of the low three bits, but the class sits on
    -- the plain ground you jump FROM, never on the lip -- pinning it raised
    -- a one-cell rail of turf along the top of every terrace.  The lip is
    -- reached from the NEIGHBOUR's class instead (TileShape's HOP_LIP),
    -- which is the only thing that can tell a knee-high side lip from the
    -- cliff face it shares its two tiles with.
    -- a door set into a facade (Johto's $37/$38/$39/$3A cells).  It is
    -- walkable -- the player steps onto it to warp -- so the cell rules
    -- resolve it to ground and punch a hole through the front of the
    -- building, which is the same failure Gen 1's door fold exists for
    [0x71] = "wall",
    -- the class CheckCounterTile tests: a service counter is something you
    -- lean on, not a wall stub
    [0x90] = "counter",
    -- THE INTERACTIVE FURNITURE CLASSES.  $90 above is the only one of
    -- these the game names in a routine; the rest are named by the table
    -- CheckFacingTileForStdScript walks (TileCollisionStdScripts,
    -- 04:$7A43), which is a straight collision -> std script map and is
    -- the ROM stating what each of these things IS:
    --
    --   $91 -> MagazineBookshelfScript   a bookshelf
    --   $93 -> PCScript                  a PC terminal
    --   $94 -> Radio1Script              a radio set
    --   $95 -> TownMapScript             the town map on the wall
    --   $96 -> MerchandiseShelfScript    a Mart's stock shelf
    --   $97 -> TVScript                  a television
    --   $9D -> WindowScript              a window
    --   $9F -> IncenseBurnerScript       a Tin Tower burner
    --
    -- Every one of them was a 16px cube before this: nothing indoors had
    -- a pin of any kind, so `forMap`'s fallback sent all of them to
    -- `wall`, and a Center's PC, a bedroom TV and a Mart's stock shelf
    -- were the same grey box in the same place.  Eight rows here reach
    -- all twenty-odd indoor tilesets at once, which is the whole reason
    -- this table is keyed by class rather than by tile.
    --
    -- $95 and $9D are deliberately absent.  A town map and a window are
    -- PAINTED ON the wall band and are not objects standing in front of
    -- it -- the fallback's 16px upright panel is already exactly right,
    -- and giving either its own depth would punch the wall open behind.
    [0x91] = "bookcase",
    -- `console`, NOT `desk`.  A desk is a box, and the upright fold gives a
    -- box its front face from the drawing's bottom row and then REPEATS the
    -- north row across its lid -- which on a PC or a television means the
    -- screen is printed twice, once facing you and once lying flat on top
    -- of the machine.  `console` is the per-pixel standee the class was
    -- written for: the screen appears once, facing out, and the cabinet
    -- keeps the silhouette it is drawn with instead of being squared off.
    [0x93] = "console",
    [0x94] = "console",
    [0x96] = "bookcase",
    [0x97] = "console",
    -- drawn as a round-bellied urn, so the voxel hull rather than a box
    [0x9F] = "cylinder",
    -- $B2 is NOT a wall.  It is the ENTRANCE MAT -- the doorstep laid in
    -- front of a gate or house (Johto's $2C/$3C, where $3C is the ordinary
    -- ground tile), and the same class the cave mouths carry.  Folding it
    -- up stood a box on every doorstep in Johto, so it stays flat ground
    -- and is deliberately absent from this table; the hole in a mountain
    -- top is a terrain problem, not this one.
  },

  -- Only tiles the detector must not touch need listing. Tile ids are
  -- indices into the tileset's own 8x8 atlas.
  tilesets = {
    -- Gen 2's Johto set. Tile pins still work here -- they are read before
    -- the collision table above -- and they are the right tool wherever a
    -- drawing is finer than the 16x16 cell the class describes, which on
    -- Gen 2 is most of the outdoors: a class is stated per CELL, but a
    -- ledge lip, a fence rail and a sign board are each drawn across half
    -- of one.
    TilesetJohto = {
      -- Plain ground and open water, pinned flat against their own cells.
      --
      -- These look redundant and are the opposite. A Gen 2 tile that is
      -- not pinned falls to `wall` (the class table answers for the cell,
      -- not the tile), and the cell rules only rescue it where the cell is
      -- WALKABLE -- so every scrap of ordinary grass sharing a blocked
      -- cell with something solid stood up as a 16px box: the two rows of
      -- turf above every ledge lip, the ground beside every cliff post,
      -- the verge inside every fence corner. Same for the shoreline, whose
      -- cells are wall-class ($27) with nothing but water drawn in them.
      -- $05/$06 and $14/$58 are never anything but flat ground and water
      -- anywhere in the set.
      ground = { 0x05, 0x06 },
      water = { 0x14, 0x58 },
      -- THE PLATEAU TOP.  Gen 2 records no elevation: the Ruins of Alph
      -- courtyard rim and the grass it looks down on are both collision
      -- $00, and the four cliff drawings around them are $07 like any
      -- other solid.  The only place the drop is written down is the
      -- floor tile, and there it is unambiguous -- $3C is the dirt drawn
      -- ON TOP of a cliff and $05/$06 the grass at its foot.  Swept over
      -- twenty Johto maps $3C falls in a walkable cell 2810 times and
      -- carries only two classes doing it, $00 and $B2; $05/$06 never
      -- share a cell with it.
      --
      -- $2C is the same floor with its north LIP on it: a black shadow
      -- band under a sunlit highlight, the rim seen edge-on.  It carries
      -- collision $B2 -- the class the profile above deliberately leaves
      -- flat, because $B2 is also every doorstep in Johto -- so the pin
      -- has to be per TILE, which is exactly the split a tile pin makes:
      -- the doorsteps are drawn $40 and $3C, never $2C.
      --
      -- Left unpinned both fell to the walkable-cell rule and came out as
      -- flat ground, so every terrace in Johto -- the Ruins' four sunken
      -- courtyards, Route 32's whole east bank -- was painted onto the
      -- grass at the same height as the grass, with its own cliff face
      -- standing 16px out of the lawn beside it.
      --
      -- NOT in the collision table and NOT in TilesetForest or
      -- TilesetPark: those two reuse both ids for the forest floor, where
      -- they are drawn only in solid $07 cells and mean nothing of the
      -- sort (Ilex Forest 247 of each, the National Park 177).
      terrace = { 0x2C, 0x3C },
      -- the hop-down lip. Its own cell's class is $07 and the LEDGE
      -- classes ($A0-$A5) sit on the plain ground ABOVE the drop, so the
      -- class table cannot reach the drawing at all -- the lip was a 16px
      -- wall running the length of every terrace.
      --
      -- $4B and $4D, the run's end caps, are deliberately left as walls:
      -- they are also the inner corners of the cliff base ($0A, $6C, $6D),
      -- and nothing in the drawing tells the two apart -- both sit under
      -- the same $3B/$3D cliff post. At a run's end they read as the
      -- corner post the cliff turns on, which is what they are drawn as.
      ledge = { 0x4C },
      -- the wooden fence: $40 and $4A the vertical runs, $5A/$59 the top
      -- and bottom rows of a horizontal one. Across all 128 Johto blocks
      -- these four tiles are drawn NOWHERE else, and their cells' classes
      -- disagree ($07 for the horizontal runs, $70/$76/$7E for the
      -- vertical) -- so the class table cannot reach them and a tile pin
      -- can. Left alone they came out as 16px walls: a picket fence
      -- standing as tall as the houses behind it.
      --
      -- `post`, not `fence`: the fence class is a BOX, and a fence seen
      -- FACE ON is the one piece of scenery that is mostly holes --
      -- pickets with daylight between them, a rail with air under it. The
      -- post pool cuts the drawing per pixel and stands each CELL alone in
      -- its own depth band, so a run reads as separate panels with gaps
      -- between them rather than one fence-textured kerb.
      --
      -- $40 is NOT one of them.  It is the pink entrance mat, and the cells
      -- it is drawn in carry classes $70/$76/$7E -- the warp classes
      -- CheckWarpCollision matches ($60, $68, high nybble $7) -- so it is
      -- the doorstep you walk onto to enter a gate, not a picket.  Standing
      -- it up put a box across the front of every route gate in Johto.
      post = { 0x59, 0x5A },
      -- ...but only the EAST-WEST run.  The two projections are not the
      -- same drawing: $59/$5A are the fence seen FACE ON, pickets and
      -- daylight, which is what the standee pool is for -- while $4A is
      -- the same fence seen END ON, one 8px column repeated seamlessly
      -- down the whole run with no picket in it to see through.  Cut per
      -- cell like the face-on rows it came out as a chain of separate
      -- slabs, each in its own depth band, stepping away from the camera
      -- and stopping short of the run it is supposed to meet (Route 35's
      -- north-south line, the pen around Sprout Tower).  `fence` is the
      -- continuous kerb the end-on view actually depicts, and at the
      -- face-on run's own height the two meet flush at the corner.
      fence = { 0x4A },
      -- ...and the face-on rows are also what the end-on run is BUILT
      -- from: a 6px panel down the middle of the cell wearing $5A over
      -- $59 on both flanks, so a first-person walk along it sees pickets
      -- rather than one long plank.  See Structures' buildRails.
      rail_face = { 0x5A, 0x59 },
      heights = { fence = 16 },
      -- the flowerbed ($03, drawn in block $04 and nowhere else). It sits
      -- in a walkable cell, so the cell rules made it flat painted ground;
      -- `flower` keeps that ground and stands the blooms up on it as a
      -- one-voxel cutout that sways with the tile animation.
      flower = { 0x03 },
      -- the town sign: one cell, $4E/$4F over $5E/$5F, drawn nowhere else
      -- in the set. A board on a post is a flat panel standing up, not a
      -- block of masonry, so it takes the per-pixel standee the Gen 1
      -- signs take rather than the volume path's box.
      signpost = { 0x4E, 0x4F, 0x5E, 0x5F },
      -- the tree WALL -- the forest that borders every route and fills
      -- every town's verges. Its drawing is one canopy 16px wide and TWO
      -- CELLS high: $1E/$1F the crown, $2E/$2F the middle course, $3E/$3F
      -- the underside. The lone tree beside it is the SAME crown over the
      -- SAME underside with the middle course left out, one cell tall, and
      -- the collision table already rounds that one off ($15). This is the
      -- other half of the same drawing and nothing but the middle course
      -- separates them, so it is what the rules below read.
      --
      -- `planter` is the class for a round drawing stacked two cells high
      -- on one cell of plot -- the Centers' potted plants -- and a tree is
      -- that shape exactly: the crown is HEIGHT, overhanging the cell it
      -- is drawn in, and the plot is the cell under it. Left to the volume
      -- path the whole forest came out as one flat-topped green plateau
      -- with the canopy pattern printed on its lid.
      --
      -- $2E/$2F carry the pin outright: across all 128 blocks they are
      -- drawn in block $05 and nowhere else, so they are never anything
      -- but the middle of a tall tree. $1E/$1F cannot be, because they are
      -- also the lone tree's crown -- what tells the two apart is what is
      -- drawn UNDER them, the middle course or the underside.
      planter = { 0x2E, 0x2F },
      -- ...but not the potted plant's SPRAY. The class caps the crown's
      -- top rows to a five-voxel slab because a pot plant's leaves are a
      -- flat fan, and a tree's are not: capped, the forest came out as
      -- rows of thin cards where the lone tree beside it -- the same
      -- crown, revolved in full -- is a ball. Off, every drawn row turns
      -- the whole 16px it is drawn at and the two match.
      planter_spray = false,
      when_below = {
        [0x1E] = { { below = { 0x2E }, class = "planter" } },
        [0x1F] = { { below = { 0x2F }, class = "planter" } },
      },
      cylinder = { 0x1E, 0x1F, 0x3E, 0x3F },
      -- $4C is the cliff's FOOT as well as the ledge's lip -- the same
      -- eight pixels of dark rim, and the mountain drawings ($0A, $6C-$6F,
      -- $72, $73) end on a course of it. There it is the bottom band of a
      -- wall and must keep the wall's height, or every cliff gets a notch
      -- cut round its base. What separates the two is what stands above:
      -- open ground over a ledge, more cliff over a cliff.
      when_above = {
        [0x4C] = { { above = { 0x3C, 0x4B, 0x4C, 0x4D }, class = "wall" } },
      },
    },

    OVERWORLD = {
      -- the hop-down edges named by data.field.ledges' ledgeTile: their
      -- art is a ground lip seen from above, which the detector would
      -- otherwise raise as a wall
      -- $34 is the cliff slope's FOOT, and it also punctuates the ledge
      -- rows: the hop-down runs are set into the cliff face and this
      -- tile is the pillar between segments.  It was `wall` with the
      -- rest of the slope chain, which stood those pillars 16px beside
      -- a 6px lip -- the ledge line came out interrupted by blocks
      -- nearly three times its height.  At ledge height the run reads
      -- as one continuous lip, and the mound loses nothing: its foot
      -- row simply reads as the talus it is drawn as.
      ledge = { 13, 29, 39, 52, 54, 55 },
      -- trees are drawn ROUND -- the lone canopy (42/43/58/59) and the
      -- border tree wall (64/65/80/81, blockset $0F). Boxes and per-pixel
      -- cutouts both read wrong for them; the cylinder archetype carves
      -- one voxel ball per 16x16 cell from the canopy's darkest-pixel
      -- outline, round in depth, so tree rows become rows of real canopies
      cylinder = { 42, 43, 58, 59, 64, 65, 80, 81 },
      -- the town sign (blockset 8's SE cell): a standing per-pixel slab
      -- 2 voxels thin, transparency respected -- never a solid box
      signpost = { 70, 71, 86, 87 },
      -- the fence posts drawn in VERTICAL runs (14 the post tops, 85
      -- the bottoms -- across all 222 maps the two tiles pair only in
      -- this one cell). The detector already turns the HORIZONTAL runs
      -- (tile 57) into per-post standees, but a vertical run of repeated
      -- cells trips its scenery guard and fell to the volume path as a
      -- fence-textured tower. `post` extracts each cell alone, so these
      -- render as the same thin posts, marching north
      post = { 14, 85 },
      -- the cliff-mound's dark east slope and its NE corner ($24 the
      -- slope column, $02 the corner).  Their drawn runs span the whole
      -- mound drawing, so the detector raised them to 32px towers --
      -- the rock pillar beside Diglett's Cave -- and the doorway
      -- column, which adopts its REGION's height, inherited the same 32
      -- and put the cave entrance a block above the mound around it.
      -- Pinned to one 16px course they match the plateau body, and the
      -- doorway drops with them.  ($34, the slope's foot, is `ledge`
      -- instead -- see there.)
      wall = { 2, 36 },

      -- the cuttable bush ($2D/$2E/$3D/$3E, the four tiles Cut deletes
      -- -- across the whole tileset they appear only in the five
      -- cut-tree blocks): a standing per-pixel cutout 5 voxels deep,
      -- black-outline segmented with the pixels the outline encloses
      -- kept, its drawn grass dither flooding away as background
      prop = { 45, 46, 61, 62 },
      -- the ground painted under those pinned props, by the prop tile's
      -- own id: the bush stands on plain grass ($2C) -- the very tile
      -- Cut leaves behind (field.cutTreeSwaps' after-blocks) -- rather
      -- than whatever flat tile its neighbours vote
      prop_ground = { [45] = 44, [46] = 44, [61] = 44, [62] = 44 },
    },

    -- The badge gyms and Bruno's room (one tileset): the bird statues
    -- that flank every gym's aisles, and Lt. Surge's trash cans.  A
    -- statue is one cell of figure ($02/$38/$12/$13) drawn over one
    -- cell of plinth ($22/$23/$32/$33); the trash can is one cell
    -- ($0B/$0C/$1B/$1C, blocks 38/39 only).  Across the whole blockset
    -- none of these tiles appears anywhere else.  The plinth stays a
    -- SOLID 16px block; the figure stands ON it as a per-pixel cutout
    -- 5 voxels deep (the thin `prop` pool), collapsing to the plinth's
    -- single cell of footprint (Structures' wall-support rule); the
    -- can is the same 5-voxel cutout at floor level.  Both are
    -- black-outline segmented -- backgrounds flood away, the pixels
    -- the outline encloses stay.  Everything stands on the gyms' main
    -- floor tile ($11), which is also Bruno's floor.
    -- (The boulders, $07/$08/$17/$18, are pinned round -- see the
    -- `cylinder` pool below.)
    --
    -- The rest of the tileset is the ten rooms' own furniture: the six
    -- badge gyms it serves (Pewter, Cerulean, Vermilion, Celadon,
    -- Fuchsia, Viridian) plus Bruno's and Lorelei's rooms, the
    -- Champion's room and the Hall of Fame.  (Saffron's and Cinnabar's
    -- gyms are FACILITY, Agatha's room is CEMETERY and Lance's is DOJO,
    -- so none of them takes a pin from here.)  Same failure as every
    -- other interior: the detector reads the black interior walls as
    -- volumes measured off the whole drawn run, so Vermilion's side
    -- walls and Viridian's north-south maze arms came out as 48px fins
    -- with their black fill VOIDED flat between them, and the Hall of
    -- Fame's recording machine merged into the wall band as a 32px slab
    -- whose feet had been flattened away by the walkable-cell rule.
    GYM = {
      -- The wall band is ONE 16px face, whatever the artist drew into
      -- it.  The plinths (34/35/50/51 -- 50 is the $32 water-fallback
      -- trap and would recess into a pond lip); the room's own band
      -- ($05 white course, $10 trim, $06 the doorway's dark head); the
      -- BLACK interior walls every gym is partitioned with -- $0F the
      -- fill (near-black, so the void rule flattens it unless it is
      -- AUTHORED, which is the whole reason it is listed), $24/$26/$27
      -- the top edge and its corners, $25/$35 the sides, $42/$3E the
      -- west and east end caps of a horizontal arm and $10 again as its
      -- lit south face.  Then the things drawn built INTO those walls,
      -- exactly like the Center's healing consoles: Vermilion's target
      -- band ($44-$47 with $05 between, over the $54/$56/$57 stripe),
      -- the barred gate ($20/$21/$30/$31 -- Lorelei's north door, and
      -- the barrier VermilionGymScript paints in until both switches
      -- are thrown), and Vermilion's corner switchboard ($29/$2A over
      -- $0D/$0E and $1D/$1E), which is drawn 32px tall and so reads as
      -- two stacked courses of the same band.
      wall = { 34, 35, 50, 51,
               5, 16,
               15, 36, 37, 38, 39, 53, 62, 66,
               68, 69, 70, 71, 84, 86, 87,
               32, 33, 48, 49,
               13, 14, 29, 30, 41, 42 },
      -- Fuchsia's invisible maze walls ($1F) are deliberately NOT here.
      -- The artist drew them as the floor with its stripes broken: on
      -- the GB they are invisible, and the puzzle IS walking into them.
      -- Raising them to a course would read better as a room and give
      -- the player something to bump into -- and would also hand them
      -- the solution, turning a maze into a corridor.  A shape is
      -- purely presentational and this file's job is to reproduce what
      -- was drawn, so the drawn answer wins: left to the derived path,
      -- $1F stays the floor it is painted as and the gym plays exactly
      -- as the flat game does.
      -- Cerulean's pools are the ONE place the $14 water-fallback trap
      -- is right: $14 really is the gym's water, so it is left to fall
      -- through to the engine's water set and recess.  Its north coping
      -- ($04, the grated lip) is drawn in the TOP half of a water cell,
      -- so the cell rule dragged it down to the water line with it;
      -- pinned flat it stays the poolside at floor level and the water
      -- shows a real lip.  The pool's south lip ($01) needs nothing --
      -- it is always the top half of a walkable FLOOR cell, so rule 3
      -- already lays it flat.  Lorelei's room uses the same pair for
      -- the paved plaza that stands out of her water.
      -- the entrance mat every gym lays inside its door ($06 over $16,
      -- 28 placements and nowhere else): drawn from straight above, so
      -- it lies FLAT.  $06 was in the wall band above, which stood the
      -- mat's top half up as a 16px box in the doorway -- the cell rule
      -- could not save it, because a pin outranks the cell.
      ground = { 4, 6, 22 },
      -- Celadon's hedge: a round shrub, one per cell ($2C/$2D over
      -- $2E/$2F), 35 of them planted wall to wall.  Round drawings get
      -- the cylinder archetype -- one voxel ball per 16x16 cell carved
      -- from the darkest-pixel outline -- the same treatment the
      -- overworld's tree canopies take, and per-CELL, so a hedge row
      -- becomes a row of bushes instead of one boxed monolith.
      --
      -- The rock gyms' boulder ($07/$08 over $17/$18) is the same
      -- reading: one cell is one rock, drawn as a lit dome -- white
      -- highlight up the north-west, mid-grey body, black-and-grey
      -- rubble dither filling the rest -- with the FLOOR showing
      -- through all four corners, which is what makes a run of them
      -- read as a pile of separate stones rather than a wall (tile
      -- them and the gaps between four rocks draw a grey diamond).
      -- Left derived it fell to the repeat-aware scenery path, which
      -- extruded the whole drawing as one 16px course: Pewter's and
      -- Bruno's rock rows came out as square bars wearing a boulder
      -- texture in relief -- the extruded picture.  Round-pinned,
      -- each cell is a hull whose plan view is its own drawn width
      -- profile turned in depth: a dome 16 wide and 16 tall, full
      -- width from the drawn shoulder down and tapering over the top
      -- five rows exactly where the art tapers, and the corner
      -- diamonds open up between them the way the drawing has them.
      -- It stays 16px, so nothing that stands on or beside a rock
      -- moves.  The perimeter rows take the same model as the maze
      -- clusters -- one drawing, one rock, everywhere.
      -- Scanned: across all 222 maps these four tiles occur 87 times
      -- on this atlas and every one of them anchors a whole boulder
      -- cell (87 tile-$07 hits, 87 grid matches), in exactly two maps
      -- -- PEWTER_GYM's walls and rock maze, and BRUNOS_ROOM's
      -- clusters.  DOJO shares gym.png but places none of them, so
      -- the pin is not copied there.
      cylinder = { 44, 45, 46, 47,
                   7, 8, 23, 24 },
      -- Vermilion Gym's trash cans ($0B/$0C over $1B/$1C), the switch
      -- puzzle's fifteen cans plus the sixteenth beside the leader's
      -- platform.  An open galvanised bin in the 3/4 view, and its plan is
      -- measured: the silhouette runs straight down both flanks for art
      -- rows 4-10 and is 11px wide there, so the can is 11 across -- and
      -- being round in plan, 11 DEEP.  Above row 4 is the MOUTH seen from
      -- above (the drawn ring is 9x5, a circle flattened to 55%, which is
      -- what fixes it as a top view rather than a face-on dome); below row
      -- 10 is the base circle's front arc, ground contact, with the
      -- drawing's own $555 halo one pixel outside it as the grounding
      -- shadow.
      --
      -- Left in the thin standee pool the can was a flat disc on edge --
      -- fifteen coins standing in a row.  Pinned a plain `cylinder` it
      -- revolves every drawn row, bottom arc included, and comes out a
      -- barrel balanced on a three-voxel stem.  `can` is the hull cut at
      -- both ends and hollowed: the mouth projects across the round top,
      -- the base rows are ground rather than body, and the top can_well
      -- voxel rows keep a wall at each end of every chord and lose their
      -- middle, so the bin is open and you look down into it.
      --
      -- can_cap and can_base are the two ellipses in art rows and come off
      -- the pixels.  The other three do NOT, and are the numbers taste
      -- moves:
      --
      --   can_height 9    Un-projected strictly the drawing states a squat
      --                   drum barely two rows of straight side tall,
      --                   because the GB artist spent most of a 16px cell
      --                   on the opening -- but a bin is taller than it is
      --                   wide and the flat game reads as one, the drawing
      --                   being 14px tall beside a 16px player.  The lowest
      --                   surviving body row (art row 10: black rim, shaded
      --                   flank, lit face) is repeated up to this, the
      --                   plainest continuation of the material drawn.
      --                   `heights` must follow it so anything riding a can
      --                   lands on the rim.
      --   can_well 5      How far down the mouth is hollowed.  The drawing
      --                   paints an opening and cannot say how deep.
      --   can_taper 4     Voxels of DIAMETER the base loses -- 11 at the
      --                   rim to 7 on the floor, stepped twice over the
      --                   height.  The drawing's base arc pulls in to 9px
      --                   on its own, so the direction is drawn; the amount
      --                   is not.  2 is one barely-visible step, 4 reads as
      --                   a cone.
      --
      -- Scanned: the four ids occur as this grid 16 times on the GYM atlas
      -- and only in VERMILION_GYM -- cells (1/3/5/7/9, 7), the same five
      -- on rows 9 and 11, and (6,1).  DOJO shares gym.png and places none,
      -- so the pin is not copied there.  The same four ids form the same
      -- grid on eight OTHER atlases (the Bike Shop's crates, the overworld
      -- roofs, the Centers' counters, ...) for 142 more hits; those are id
      -- collisions between tilesets, and a pin is per tileset id, so they
      -- are none of this entry's business.
      can = { 11, 12, 27, 28 },
      can_cap = 9,
      can_base = 4,
      can_height = 9,
      can_well = 5,
      can_taper = 4,
      heights = { can = 9 },
      -- The statues and Celadon's three little trees ($40/$41 canopy over
      -- $50/$51 trunk).  A trunk is not round, so the tree cannot be a
      -- ball like the shrubs beside it -- it takes the thin standee pool
      -- every interior plant takes, which is also a pool apart from the
      -- cylinders it touches.
      prop = { 2, 56, 18, 19,
               64, 65, 80, 81 },
      -- The Hall of Fame's recording machine, the one piece of real
      -- furniture in the tileset.  It is drawn 32px wide and THREE tile
      -- rows tall against the north band, and the detector made a mess
      -- of it twice over: the top two rows merged into the wall band as
      -- one 32px slab, and the base row -- whose cell is walkable,
      -- because the Hall's floor tile ($19) is its own bottom-left --
      -- was flattened into the floor, so the machine stood on nothing.
      -- Split at the drawn seam: the plinth row ($58/$59/$5A) is a
      -- half-cell counter, and the console above it ($5B-$5E over
      -- $36/$37/$55/$5F) is a standing per-pixel billboard that rides
      -- the plinth's top face through the authored-box support rule.
      -- 8 + 16 is exactly the 24px the machine is drawn.
      counter = { 88, 89, 90 },
      billboard = { 91, 92, 93, 94, 54, 55, 85, 95 },
      -- the ground painted under each pinned prop, by the prop tile's
      -- own id: statues and cans stand on the gyms' main floor ($11),
      -- Celadon's trees on the garden's light dither ($2B) rather than
      -- on whatever their neighbours vote.
      -- (Celadon's flowerbed tile $03 is deliberately absent: the
      -- tileset ANIMATES it by frame rewrite, so TileShape derives the
      -- `flower` pin for it already -- flat ground plus a standing
      -- 1px cutout -- and listing it here would take that away.  The
      -- floors need nothing either.  $11/$16/$2B and Viridian's arrow
      -- and dot markings $3C/$3D/$3F/$4C/$4D are in the walkable list
      -- outright; the paved slabs the Hall of Fame is floored with and
      -- Lorelei's plaza is built of ($09/$0A over $19/$1A) get there
      -- through the CELL: only $19 is listed, but it is the cell's
      -- bottom-left, so rule 3 lays all four of them flat together.
      -- Cerulean uses the very same slab as its poolside deck, which is
      -- why that gym's perimeter is a deck and not a wall -- the room's
      -- only wall band is the one drawn course along its north edge.)
      prop_ground = { [2] = 17, [56] = 17, [18] = 17, [19] = 17,
                      [11] = 17, [12] = 17, [27] = 17, [28] = 17,
                      [64] = 43, [65] = 43, [80] = 43, [81] = 43 },
    },

    -- The caves: one blockset serves nineteen maps -- Mt Moon's three
    -- floors, Rock Tunnel's two, Seafoam Islands' five, Victory Road's
    -- three, Cerulean Cave's three, and Diglett's Cave with its two
    -- route-side stubs.
    --
    -- THE CAVE'S VERTICAL SCHEME.  A Gen 1 cave is drawn on two floor
    -- levels, and the game's own collision data says which is which.
    -- data.field.tilePairs forbids stepping between $20/$21/$2A/$41 and
    -- $05 on land, and between $14 and $05 while SURFING -- but nothing
    -- forbids $14 <-> $20.  Read that back and the elevation falls out:
    -- the dark floor and the water are one plane, the lit floor is a
    -- step above both, and the rock is the room around them.
    --
    --        h  what                                 tiles
    --        0  DARK LOWER FLOOR -- the datum         $20 $21 $2A
    --        0  CAVE WATER, the surfable pool         $14
    --        0  fall-through drop hole                $2F $22
    --        0  unlit black (the void rule, no pin)   $3C
    --        3  Victory Road's boulder switch plate   $2B $2C $2D $2E
    --        6  LIT SHELF, one step up (`ledge`)      $05 $29
    --        6  the stair plate down off that shelf   $15 $16
    --       16  ROCK -- one band for the masses, the  everything else
    --           faces, the caps and the ceiling mass
    --   0 up 16  ladder shaft UP a floor              $0A $0B $1A $1B
    --   0 dn 16  ladder shaft DOWN a floor            $08 $09 $18 $19
    --
    -- NO CAVE SURFACE SITS BELOW 0.  The datum is the dark floor; the
    -- water is level with it (you surf off a pool straight onto the dark
    -- floor, which is exactly what the missing $14/$20 tile pair says);
    -- every other surface is above it.  A cave is underground, not
    -- underwater, and the only class in this file that goes negative is
    -- `water` (-2), which exists to cut the overworld's shoreline lip.
    -- It is deliberately NOT used anywhere in this entry.  The one thing
    -- that does reach below the datum is the DOWN ladder's stairwell,
    -- which is a hole on purpose: it is the shaft to the floor below,
    -- and no walkable surface is drawn in it.
    --
    -- What the detector made of it: the rock EDGES towered.  A shelf's
    -- side is drawn as a cap over a run of face tiles over a corner
    -- pair -- $04 / $31 x5 / $28 / $10 down one column -- and the volume
    -- builder's repeat scan anchors on the column's FRONT tile, which
    -- here is a one-off corner that never recurs above it.  Neither the
    -- repeat read nor the trim rule (two identical rows directly above
    -- the front) fires, so the column keeps its whole extent and caps at
    -- MAX_ROWS: a 48px fin out of the 16px band beside it, while the
    -- column one tile west -- ending on $28 with two $31 above -- reads
    -- 16.  Probed before pinning: MT_MOON_B2F tiles (5,4)-(5,11) and
    -- (17,8)-(17,15) at 48 with 16 either side; VICTORY_ROAD_2F
    -- (25,26)-(25,31); SEAFOAM_ISLANDS_B4F (22,0)-(22,7),
    -- (13,12)-(13,19) and (12,13)-(12,19).  The same reading turns a
    -- column of four DIFFERENT rock tiles into 32px -- VICTORY_ROAD_1F
    -- (28,20)-(29,23) and (30,20)-(31,23), $02/$12 over $0C/$1C, next
    -- to identical rock at 16.  An authored tile never reaches the
    -- volume builder, so pinning the rock is the whole fix: there is no
    -- run left to misread.
    CAVERN = {
      -- ---- 16: the rock, one band ----
      --
      -- Reading across the blockset: $02/$03 over $12/$13 is the
      -- speckled rock mass and $0C/$0D over $1C/$1D the boulder-cluster
      -- mass, both solid wall-to-wall fills; $10/$11 is the cobble
      -- course facing the south side of every lit shelf, $31 its west
      -- face and $17 its east; $04/$07/$28 are the caps and $25/$26 the
      -- inner corners where two faces meet.  $0E/$0F over $1E/$1F is the
      -- barred rock shelf that stands alone on the dark floor
      -- (MT_MOON_1F, ROCK_TUNNEL_1F and twice in SEAFOAM_ISLANDS_B4F):
      -- one cell of face-on drawing, so one 16px face -- never a
      -- standee, its black surround touches all four rims and would
      -- segment into a solid slab.
      --
      -- $06/$27 over $24/$01 is the CEILING MASS: a pale dithered rock
      -- fill with a black rim dithered along its north and south edges,
      -- so a run of it tiles into the grid of light blocks that walls
      -- off most of MT_MOON_B2F (37 cells) and stands as one lump in
      -- each of VICTORY_ROAD_1F/2F/3F.  It is blocked in every map that
      -- places it ($24 is not on the walkable list) and it is NOT in the
      -- engine's water set, so it is rock and belongs in the band with
      -- the rest of the rock.  The first pass read the checker as a pond
      -- and pinned it `water`: that recessed 612 tiles to -2 and cut
      -- open trenches down the middle of Mt Moon B2F -- 06w-2 27w-2 /
      -- 24w-2 01w-2 for ten cells straight, hard against 31w16 rock and
      -- the 05l06 shelf.  Its unpinned reading was 48px (eight rows of
      -- alternating $06/$24 read as one drawing); 16 is the answer.
      wall = { 2, 3, 18, 19,       -- $02/$03 over $12/$13, speckled mass
               12, 13, 28, 29,     -- $0C/$0D over $1C/$1D, boulder mass
               16, 17,             -- $10/$11, the shelf's south cobbles
               49, 23,             -- $31 west face, $17 east face
               4, 7, 40,           -- $04 NW cap, $07 NE cap, $28 SW cap
               37, 38,             -- $25/$26, the inner corners
               14, 15, 30, 31,     -- $0E/$0F over $1E/$1F, barred shelf
               6, 39, 36, 1 },     -- $06/$27 over $24/$01, ceiling mass
      -- ---- 6: the lit shelf, and the stairs off it ----
      --
      -- $05 is the lit floor -- the shipped pin, and the step
      -- data.field.tilePairs encodes ($20/$21/$2A/$41 <-> $05).  $29 is
      -- the SAME surface: the artist's shadow row where the shelf runs
      -- up against the rock above it.  It sits in walkable cells, so
      -- unpinned it resolved to flat ground and cut a 6px trench along
      -- the north edge of every lit room (`29g00` with `05l06` one tile
      -- south, all the way across MT_MOON_B2F).
      --
      -- $15/$16 is the STAIR down off that shelf, and the elevation it
      -- spans is 6px, not 16.  Its art is four treads seen from above,
      -- each a light tread over a black riser line, stacked NORTH-SOUTH:
      -- every one of the 54 stair cells in the tileset has the lit floor
      -- $05 to its NORTH and the low ground to its SOUTH (dark floor x35,
      -- water x14, lit floor x5 where two flights meet), so the flight
      -- climbs NORTHWARD, one cell deep, 0 -> 6.
      --
      -- It is NOT pinned `stair_e`/`stair_w`, and that is deliberate.
      -- Those classes build a flight that marches along X -- 16px tall,
      -- rising toward the named side -- so either of them here would
      -- throw a 16px staircase sideways across a 6px north-south step,
      -- blocking the passage it is supposed to open and climbing at
      -- right angles to the drawn risers.  A wrong-way flight is worse
      -- than a flat one.  `ledge` is the honest reading available: the
      -- stair cell joins the shelf it belongs to, wears its four treads
      -- on the TOP face (which is how they are drawn -- from above), and
      -- puts its 6px riser face at the FOOT of the flight where the
      -- player actually steps down onto the dark floor.  See the report:
      -- a real sloped cave stair wants `stair_n`/`stair_s` in
      -- Structures.stairCell, which is an engine change, not a pin.
      ledge = { 5, 41,             -- $05 lit floor, $29 its north shading
                21, 22 },          -- $15/$16, the stair plate off it
      -- ---- 0: the floor plane ----
      --
      -- The dark lower floor, pinned rather than left derived so the
      -- datum this whole entry measures from is stated in it.  $20 is
      -- the rough floor, $21 the bright checker, $2A the fine checker;
      -- all three are on the tileset's walkable list and all three
      -- already resolved here -- the pins restate the level, they do not
      -- move it.
      --
      -- $14 IS THE CAVE WATER: the tileset animates by TILEANIM_WATER,
      -- and TileRenderer's WATER_TILE is $14 -- it is the tile that
      -- h-shifts to ripple.  Map's water set names it too, so its cells
      -- are the ones Surf works on: Cerulean Cave's lake (352 + 272
      -- tiles on 1F/B1F) and the Seafoam channels (304 on B3F, 816 on
      -- B4F).  The first pass read its blocky white dither as "bright
      -- rubble mass" and pinned it `wall`, which stood both lakes up as
      -- 16px rock -- two thirds of SEAFOAM_ISLANDS_B4F was a rock slab
      -- you were meant to surf across.  It is water, and it lies at the
      -- floor plane: `ground` keeps the drawn (and animated) water art
      -- exactly as it is and puts its surface at 0, level with the dark
      -- floor you step off onto, one 6px step below the lit shelf you
      -- cannot surf onto.  NOT the `water` class -- that is -2, a
      -- shoreline lip for the overworld sea, and a cave pool must never
      -- read as a trough sunk into the floor you are walking on.
      --
      -- $2F over $22 is Seafoam's and Victory Road's fall-through drop
      -- hole (Map's warpPadTiles calls $22 a "hole").  Its art is a lit
      -- rim over solid black and its cell is walkable -- you step on it
      -- and drop a floor -- so it stays flat at the floor plane; the pin
      -- keeps the rim out of the wall fallback.
      ground = { 32, 33, 42,       -- $20/$21/$2A, the dark lower floor
                 20,               -- $14, the surfable cave water
                 47, 34 },         -- $2F over $22, the drop hole
      -- ---- 0 to 16: the ladders, the caves' real staircases ----
      --
      -- Both ladder graphics are drawn from above as a shaft with two
      -- rails and rungs between them, and which one is which is not a
      -- guess -- it is in the warp table.  Across all nineteen maps,
      -- every one of the 37 $08 cells warps to a LOWER floor
      -- (MT_MOON_1F->B1F, B1F->B2F, ROCK_TUNNEL_1F->B1F, each
      -- SEAFOAM_ISLANDS floor to the next one down, CERULEAN_CAVE_2F->1F
      -- and 1F->B1F, the Diglett's route stubs down into the cave) and
      -- every one of the 40 $0A cells warps to a HIGHER one (the exact
      -- reverse, plus MT_MOON_B1F's and ROCK_TUNNEL_1F's exits back out
      -- to daylight).  $08 is the ladder DOWN, $0A the ladder UP: 77
      -- cells, no exceptions.
      --
      -- So they take the two classes that MOVE between floors.  $0A
      -- becomes a rising flight -- four real steps climbing 0 -> 16, the
      -- height of the rock band it disappears into -- and $08 becomes an
      -- excavated stairwell, four steps descending below the floor into
      -- a dark opening.  East for both: the ladder art is symmetric
      -- about its own centre line so the drawing does not choose a side,
      -- the cell's east neighbour is the closed (rock) side more often
      -- than its west, and the rest of this profile's staircases
      -- (REDS_HOUSE_1, UNDERGROUND) climb east too.  The flight's treads
      -- land one rung apiece, which is as close to a drawn ladder as
      -- stepped geometry gets.
      --
      -- All four tiles of each cell are listed, the way REDS_HOUSE_1
      -- lists its flight: buildStairs anchors on the cell's TOP-LEFT
      -- tile ($08 / $0A) and claims the other three, but pinning them
      -- too keeps them out of the region flood and the door fold.
      stair_e = { 10, 11, 26, 27 },        -- $0A/$0B over $1A/$1B, UP
      stair_down_e = { 8, 9, 24, 25 },     -- $08/$09 over $18/$19, DOWN
      -- ---- 3: the boulder switches ----
      --
      -- Victory Road's four plates ($2B/$2C over $2D/$2E, on 1F, 2F and
      -- 3F).  Round art, but NOT a round object: the Strength boulders
      -- themselves are overworld SPRITES, and this is the plate they get
      -- pushed onto -- drawn from straight above as a black ring, a
      -- white highlight rim and a grey disc.  `cylinder` was tried here
      -- first, because a circle is what the overworld's round canopies
      -- take, and it came out wrong: the plate's own dithered background
      -- carries stray black pixels the darkest-outline flood cannot
      -- reach, so they joined the mask, inflated the top and bottom row
      -- spans to the full 16, and the hull rendered as a clutch of white
      -- shards standing where the plate should be (VICTORY_ROAD_1F cell
      -- 17,13).  `relief` is the reading anything drawn from above
      -- wants: the disc stays flat and the pixels inside its black ring
      -- lift a few voxels, so it reads as a plate -- and the cell is
      -- walkable, so you step on it.
      relief = { 43, 44, 45, 46 },
      -- Left to the derived default on purpose: $3C is solid black --
      -- the unlit rock that is most of MT_MOON_B1F -- and the void rule
      -- flattens it (`3Cv00`).  Pinning it would BREAK that, since the
      -- void rule skips authored tiles; a 16px black band there would
      -- also wall the corridors in with something the 2D art draws as
      -- nothing at all.  $30 and $41 are on the walkable list and in
      -- tilePairs but no block in this tileset places either, so there
      -- is nothing for a pin to catch.
    },
    -- Viridian Forest.  Nearly everything drawn here is ROUND, and the
    -- detector was boxing all of it: the big trees came out as ragged
    -- mixed-height volumes (their sparse canopy-edge tiles read 0px,
    -- their bodies 32px), the stump rows merged into 16px crate walls
    -- wearing folded stump art, and the trail sign was a broken pile --
    -- its $32 tile is the water-fallback trap and recessed into a pond
    -- lip in the middle of the woods.
    FOREST = {
      -- the hop-down edge, from data.field.tilePairs (CAVERN's entry
      -- above carries the same note for its own pair)
      ledge = { 46 },
      -- the big trees: the whole 2x2-CELL drawing carves as ONE 32px
      -- voxel hull, so a tree is a single tall canopy instead of four
      -- ground-level quarter-pancakes ("cut in half", as the first
      -- attempt read).  `canopy` pins the drawing's top-left corner
      -- tile ($04) as the group anchor; every other tile of the
      -- drawing stays `cylinder` so the group build can verify and
      -- claim its cells -- and so a stray partial drawing degrades to
      -- per-cell hulls rather than boxes
      canopy = { 4 },
      cylinder = { 5, 6, 7, 21, 22, 23,
                   35, 36, 37, 38, 39, 53, 54 },
      -- the stumps ($02/$03/$12/$13): a hull whose drawn top is a CUT
      -- FACE.  The body builds from the bark rows alone, and the drawn
      -- ellipse of growth rings projects onto the hull's round flat
      -- top -- its bottom arc to the south, the way the 2D art means
      -- it.  stump_cap is the ellipse's height in art rows
      stump = { 2, 3, 18, 19 },
      stump_cap = 7,
      -- the white sparkle filler inside the tree masses: flat, not an
      -- invisible zero-height box
      ground = { 0 },
      -- the trail signs: the standing thin-slab treatment every town
      -- sign gets ($32 pinned is also what lifts it out of the water
      -- trap)
      signpost = { 33, 34, 49, 50 },
    },

    -- Oak's Lab (the tileset also serves the Fighting Dojo and Lance's
    -- room, which use none of these tiles).  The free-standing shelf
    -- ranks: book rows and base pinned; the shared trim tiles above
    -- (41/42, also the lab tables' corners) are adopted as caps by the
    -- bookcase builder rather than pinned.
    DOJO = {
      bookcase = { 13, 14, 29, 30 },
      -- the lab tables (the starter-ball display and the north tables):
      -- 41/42 are also the shelf trim the bookcase builder adopts as
      -- caps, which its cap rule allows for authored table rows.
      -- Pinning stops the display frame's black corner brackets from
      -- auto-extracting into standing prisms, and the ball/Pokedex
      -- sprites ride the table's authored height.
      table = { 41, 42, 57, 59, 78, 79 },
      -- These tables are drawn 6px tall (3px slab edge over 3px base --
      -- see the lab_table entry under `buildings`), not the default
      -- table's 12: the override keeps the volume-built north tables
      -- and the band-built starter table one height, and stands the
      -- ball/Pokedex sprites exactly on the top face of both.
      heights = { table = 6 },
    },

    -- Red's room and the Copycat's room (one tileset).  The detector reads
    -- this furniture as wall-height volumes -- and merges the wall-touching
    -- table and desk INTO the wall, towering both -- so every object here
    -- is pinned to the shape it depicts.
    REDS_HOUSE_2 = {
      -- the wall band with its windows stays one 16px face
      wall = { 0, 36, 37, 52, 53 },
      -- the bed: a mattress drawn from above, half a block high
      bed = { 45, 46, 47, 61, 62, 63 },
      -- stools: a seat-high box, seat art on top, legs on the front
      stool = { 2, 3, 18, 19 },
      -- the long table under the windows, and the PC desk's body with
      -- its hutch row -- the monitor standing on it is pinned below
      table = { 38, 39, 41, 42, 43, 44, 50, 51,
                58, 59, 60, 66, 67 },
      -- standing per-pixel props, black-outline segmented.  The PC
      -- (64/65 monitor top, 32/33 monitor bottom + keyboard) is drawn
      -- above the desk's body, so it stands ON the desk; the TV stands
      -- on the floor
      billboard = { 6, 7, 22, 23, 32, 33, 64, 65 },
      -- the potted plant: mostly silhouette, so it takes the THIN
      -- standee pool
      prop = { 8, 9, 24, 25, 68, 69, 70, 71 },
      -- the small potted plant on the table: a paper-thin profile
      -- cutout standing on the tabletop, its leaf crown (in 40) included
      cutout = { 40, 54, 55, 56, 57 },
      -- the game console in front of the TV is drawn from above: it
      -- lies flat and extrudes a few voxels inside its outline
      relief = { 14, 15, 30, 31 },
      -- the staircase leads DOWN to 1F: a sunken stairwell.  The player
      -- enters at the east lip and the flight descends westward, the way
      -- the drawn railing slopes (high at the east, low at the west)
      stair_down_w = { 10, 11, 26, 27 },
    },

    -- Red's and the Copycat's ground floor (one tileset, same atlas as
    -- the floor above).  Bookcases, dining table with its flower pot,
    -- stools, the TV on the floor, and the staircase up.
    REDS_HOUSE_1 = {
      -- the `house_stool` template below stands 5 voxels and the
      -- `reds_house_table` model 6 (both the drawn elevation): whoever
      -- sits on a stool cell and whatever object sprite stands on the
      -- table rides these heights, not the 8/12px class defaults
      heights = { stool = 5, table = 6 },
      wall = { 0, 36, 37, 52, 53 },
      stool = { 2, 3, 18, 19 },
      -- the dining table (38-44/58-60); its top row also caps the
      -- bookcases below
      table = { 38, 39, 41, 42, 43, 44, 58, 59, 60 },
      -- the bookcase bodies: tall shelf boxes; their drawn top-edge row
      -- (38/41, pinned table above) becomes their top face
      desk = { 34, 35, 48, 49, 50, 51 },
      -- the TV on the floor
      billboard = { 6, 7, 22, 23 },
      -- the small potted plant on the table: a paper-thin profile
      -- cutout standing on the tabletop, its leaf crown (in 40) included
      cutout = { 40, 54, 55, 56, 57 },
      -- the staircase leads UP to 2F: a rising flight climbing east
      stair_e = { 12, 13, 28, 29 },
      -- the front-door mat: its collision tile is $14, which the engine's
      -- stale-cache fallback counts as water in every tileset, so the rug
      -- would recess into a pond lip.  It is a flat rug on the floor
      ground = { 4, 20 },
    },

    -- The generic town house (Blue's, Daisy at her table, and eighteen
    -- more homes; the schoolhouse and the trashed house reuse it too).
    -- Same failure as Red's rooms: the detector reads the furniture as
    -- wall-height volumes and towers the table, so every object is
    -- pinned to the shape it depicts.
    HOUSE = {
      -- the `house_stool` template below stands 5 voxels and the
      -- `house_table` model 6 (both the drawn elevation): whoever sits
      -- on a stool cell -- Daisy at her table -- and whatever object
      -- sprite stands on a table cell rides these heights, not the
      -- 8/12px class defaults
      heights = { stool = 5, table = 6 },
      -- the wall band stays one 16px face: blank courses, the window,
      -- the framed picture, and the schoolhouse blackboard (72-75/88-91)
      wall = { 0, 36, 45, 46, 52, 61, 62, 72, 73, 75, 88, 89, 90, 91 },
      -- stools: a seat-high box that also seats Daisy
      stool = { 2, 3, 18, 19 },
      -- the dining table (top edge 38/41 also caps the bookcases);
      -- 80-83 are its ransacked corner in CERULEAN_TRASHED_HOUSE, which
      -- stays at table height rather than de-merging into a wall stub
      table = { 38, 39, 41, 47, 54, 57, 58, 59, 60, 80, 81, 82, 83 },
      -- the bookcase bodies: book ranks (14/15 left pair, 48/49 right)
      -- and the base course; the drawn top edge (38/41, pinned table
      -- above) becomes their top face
      desk = { 14, 15, 30, 31, 48, 49 },
      -- the corner potted plants: mostly silhouette, the THIN standee
      -- pool (crown 10/11, leaves 8/9/26/27, pot 24/25)
      prop = { 8, 9, 10, 11, 24, 25, 26, 27 },
      -- the open book on the schoolhouse table: a paper-thin cutout
      -- standing on the pinned tabletop
      cutout = { 70, 71, 86, 87 },
      -- the front-door mat: same $14 water-fallback trap as Red's; flat
      ground = { 4, 20 },
    },

    -- The Pokemon Center lobby.  One tileset serves all eleven Centers
    -- and the Celadon Hotel, and VIRIDIAN_POKECENTER places every tile
    -- the other maps use, so this list -- read off Viridian -- covers
    -- them all.  (The Marts are a DIFFERENT tileset id, MART, that only
    -- shares the atlas image; pins do not carry over.)  Same failure as
    -- the houses: the detector merges the wall-touching counters and
    -- machines into the wall and towers them, and the lounge seat --
    -- which has a PERSON drawn into the tile art -- becomes a monolith
    -- wearing his face.
    POKECENTER = {
      -- the wall band stays one 16px face: striped panels (40), the high
      -- windows (92-95; 94 doubles as the map's warp tile, and pins are
      -- look-only), the pokeball poster (2/3/18/19), and the pillars
      -- (16/41) with their bases (4/5/20/21; 20 is the $14 water-fallback
      -- trap and would recess into a pond lip).  The healing machines'
      -- console face (76/77) and button panel (6/22) are ALSO wall:
      -- drawn 16px tall against the band, so wall height is their drawn
      -- height and they read as equipment jutting from it.  (The
      -- `center_heal_machine_w`/`_e` templates below claim the full
      -- 4x4 machine grids at every placement and model the console
      -- properly; these pins are the degradation path when the profile
      -- is absent.)  The near-black screen tiles must be pinned or the
      -- void rule flattens them.  What is NOT wall is the machines'
      -- two flanks -- see `prop` below.
      wall = { 2, 3, 4, 5, 6, 16, 18, 19, 20, 21, 22, 40, 41,
               76, 77, 92, 93, 94, 95 },
      -- the counters, half a cell high: top band (8) with the nurse's
      -- tray (10), front face (24/25, the game's counterTiles), left end
      -- cap (56) and the Cable Club's light sections (90/91).  8px is
      -- one clean band, so the drawn front panel stands up and the
      -- counter top stays on top; at 12 they read as wall stubs
      counter = { 8, 10, 24, 25, 56, 90, 91,
                  -- and the lounge couch's SEAT column with the man
                  -- sitting on it.  Same half-cell box: its bottom row
                  -- (43, the front base) stands up as the couch's
                  -- front, and the rows above it -- cushion (39) and
                  -- the man (37 head, 53 face) -- ride the top face in
                  -- drawn order, each exactly once.  See the note below
                  -- on why he cannot be stood upright.
                  37, 39, 43, 53 },
      -- The couch's WEST tile column: the drawing's left strip is the
      -- couch's back and arm running north-south (the seat's cushions
      -- and seams fill the east column), so it rises over the 8px seat
      -- the way a couch back does instead of lying flush in the same
      -- box.  Per-tile granularity puts the drawn ~6px strip plus a
      -- 2px sliver of cushion on the raised band -- invisible at tile
      -- scale, and the alternative is no backrest at all.  The figure
      -- anchor scans for the tallest authored UPRIGHT under the man
      -- (see Structures.buildFigure), so he keeps sitting at seat
      -- height beside it.
      backrest = { 36, 38, 42, 52 },
      -- standing per-pixel props, black-outline segmented: the healing
      -- machines' screen tops (58/59/74/75, drawn above the pinned
      -- bodies so they stand ON them) and the PC (66/70/82/86), which
      -- stands on its pinned desk
      billboard = { 58, 59, 66, 70, 74, 75, 82, 86 },
      -- The healing machines' two FLANKS, which are not the machine and
      -- not the wall: thin equipment standing on the floor beside the
      -- console, drawn against a plain light-grey ground with no floor
      -- checker in it.  `wall` boxed each of them into a solid 16px
      -- half-cell wearing its drawing in relief -- the billboard failure,
      -- one tile wide.
      --   72   the west flank of both machines, and 73 its mirror on the
      --        east machine: a pair of PIPES leaving the console and
      --        bending down into the floor in an L, the 8px motif drawn
      --        once per pipe.  Round and thin, so the THIN pool's 5px
      --        slab, per-pixel, is the whole of them; a box is a wall
      --        stub with pipework printed on it.
      --   7/13 the west machine's east flank: a KEYBOARD, one 16px panel
      --        over two tiles (keys, and the wide bar down its right).
      --        Same thin standee; the drawn panel IS its thickness.
      -- All four ids are used at these flanks and nowhere else in the
      -- game -- 12 maps, the same two cells in each -- so this pin cannot
      -- reach anything but the machines.  72 is still the $48
      -- water-fallback trap and still has to carry SOME pin; it just
      -- wanted the thin one, not the wall.  (The machine templates now
      -- claim the flank tiles too and model the hoses and keyboard as
      -- attached 3D equipment; these standee pins are the degradation
      -- path when the profile is absent.)
      prop = { 7, 13, 72, 73,
               -- ...and the potted plants -- see THE POTTED PLANTS below
               32, 33, 34, 35, 48, 49, 50, 51 },
      -- The man on the couch, cut out by hand and stood up (see `figures`
      -- below).  Nothing automatic reaches him.  A class pin resolves a
      -- whole 8x8 tile and he SHARES his tiles with the couch, so pinning
      -- them stands the furniture up with him; riding the couch's top
      -- face (what this did before) draws him lying flat on the cushion;
      -- and he cannot be segmented into a standee either, because the
      -- drawing has no background margin for a flood to enter by and his
      -- skin is the same light shade as the couch -- the mask drained 307
      -- of his 420 interior pixels, 46% of him, even segmented alone.
      -- An authored mask is the only thing that can tell a man from the
      -- sofa he is painted into, so that is what `figures` carries.
      -- the PC's desk body, which the PC stands on
      table = { 9, 88 },
      -- THE POTTED PLANTS: a leaf crown (32/33/48/49) over an urn
      -- (34/35/50/51; 50 is the $32 water-fallback trap), the most
      -- repeated interior prop in the game -- 78 placements over 13 maps
      -- across this id and MART (scan: six per Center, two in the
      -- Celadon hotel's lounge rows, four in the Plateau lobby).
      --
      -- A plant is the THIN pool's textbook case: the drawing is ONE
      -- organic silhouette -- crown, 3px stem, urn, all 8-connected,
      -- 350 of the block's 512 pixels -- so it stands as a per-pixel
      -- cutout 5 voxels deep at its real drawn height, 32px over the
      -- two stacked cells.  Its lowest drawn row is the block's bottom
      -- row, so it stands in the pot cell's south band -- drawn low,
      -- near the front of its blocked plot -- and the crown overhangs
      -- the stem the way the drawing says, which no box or hull cut to
      -- cell granularity can do.  Both cells' tiles carry the pin (in
      -- `prop` above); the pool clusters them into one drawing, and the
      -- two side-by-side placements (every map pairs or quads them)
      -- share one cluster whose per-pixel geometry is identical to two
      -- separate ones.
      -- The plant drawing has no floor margin to vote from: the urn's
      -- #555 foot lies flush on the block's bottom edge, so the rim
      -- vote reads "dark" as background and drains the urn's own body.
      -- Name the background outright instead: the floor showing
      -- through the crown's gaps is white+light and nothing else,
      -- while the crown's own white/light highlights are sealed inside
      -- its black/#555 outline -- a light+white flood from the ring
      -- reproduces the extract mask exactly, leaves intact.
      prop_bg = { { tiles = { 32, 33, 34, 35, 48, 49, 50, 51 },
                    shades = { "light", "white" } } },
      -- THE MAN ON THE COUCH.  He is drawn INTO the lounge furniture and
      -- spills out of it in BOTH directions, which is why he needs three
      -- tile columns:
      --
      --   36 / 52   the couch's west arm.  36's two RIGHTMOST columns are
      --             the back of his head; 52 is the plain arm, and is also
      --             what 36 wears once his hair comes off it
      --   37 / 53   him: head, then face and body
      --   57 / 60   the floor east of the couch, which his hair and his
      --             foot overhang.  1 and 26 are those same two floor
      --             tiles as the artist drew them WITHOUT him -- 8 and 5
      --             pixels apart respectively -- so lifting him off is
      --             lossless there
      --
      -- `pixels` is the hand-drawn line between the man and the furniture;
      -- `under` is what each tile wears once he is lifted off it.  The
      -- couch keeps its polygonal box and he stands on top of it.
      --
      -- The mask keeps ALL of 37/53's column 7, the couch's east edge.
      -- Where that column is drawn dark it is the couch's own rule -- but
      -- it is also where his hair crosses the tile seam, so dropping it
      -- floats the overhang free of his head.  And where it is drawn WHITE
      -- it is the right side of his face, so dropping it opens a slit down
      -- his cheek (rows 5-8, which is exactly what the first cut did).
      -- Keeping the rule twice costs nothing: tile 39 redraws it on the
      -- couch beneath him either way.  Repainting 36 as 52 does cost one
      -- row -- 36's top trim band, which 52 does not carry -- and that is
      -- the accepted price for not leaving a second copy of his head lying
      -- on the arm.  The background corners around his head and the
      -- cushion wedge under his legs are the only pixels given back.
      figures = {
        {
          w = 3,
          tiles = { 36, 37, 57,
                    52, 53, 60 },
          under = { 52, 39,  1,
                    52, 39, 26 },
          pixels = {
            "..........XXXXX.........",
            "........XXXXXXXX........",
            ".......XXXXXXXXXX.......",
            "......XXXXXXXXXXXX......",
            "......XXXXXXXXXXXX......",
            "......XXXXXXXXXXX.......",
            "......XXXXXXXXXXX.......",
            "......XXXXXXXXXXX.......",
            "........XXXXXXXXX.......",
            "........XXXXXXXX........",
            "........XXXXXXXX........",
            "........XXXXXXXX........",
            "........XXXXXXXXX.......",
            ".........XXXXXXXXX......",
            "...........XXXXXX.......",
            "..............XX........",
          },
        },
      },
    },

    -- The Poke Marts (one 4x4 layout serves every city; the tileset
    -- shares the Center's atlas image but is its own id, so the pins
    -- above do not carry over).  Same failures as everywhere indoors:
    -- the detector towered the whole north display band to 32px, merged
    -- the clerk's booth into a 48px slab wearing the juice poster, and
    -- boxed the two free-standing shelf racks into one 4-tile-deep
    -- monolith.
    MART = {
      -- THE BACK WALL.  It is drawn FOUR tile rows tall -- trim (40, or
      -- the fridge tops 90/91), the SALE signs (78/79) or glass upper
      -- (44/45), the black display niche (76/77) or glass lower (46/47),
      -- and the cases' base and goods (23/29, 62/63) -- which is 32px of
      -- artwork depicting ONE wall, not four things at four depths.
      --
      -- Pinned `wall` that is exactly what it became: every row got its
      -- own 16px box marching north, so the only face you ever saw was
      -- the southmost row (the cases' base), the signs and the niche hid
      -- behind it, and the trim ended up lying flat as a gold shelf on
      -- the roofs of the boxes behind.  Laid out in depth instead of
      -- stacked up.
      --
      -- `bookcase` is the class that collapses a tall drawing onto a
      -- one-cell-deep box at its real drawn height, so the run of four
      -- rows becomes a single 32px wall: bands from the south are base,
      -- niche, sign, trim, its top face wears the trim, and the three
      -- rows behind become hidden floor.  Same treatment the shelf racks
      -- below already get -- a Mart's back wall IS a wall of display
      -- cases, and the geometry does not care which we call it.
      bookcase = { 23, 29, 40, 44, 45, 46, 47, 62, 63, 76, 77, 78, 79,
                   90, 91,
                   -- the free-standing shelf racks: TALL drawings, not
                   -- deep ones -- each rank collapses onto a
                   -- one-cell-deep shelf at its drawn height (the
                   -- Dojo/Red's-house treatment). 64/65/67 and 80/81/83
                   -- are the bottle rows the clerk's booth also wears as
                   -- its top display; 68/69/71 and 84/85/87 the goods
                   -- rows below
                   64, 65, 67, 68, 69, 71, 80, 81, 83, 84, 85, 87 },
      -- The wall's own tiles are reused elsewhere, and the back wall is
      -- the one place they are drawn on the map's TOP EDGE.  So `bookcase`
      -- is their default and this hands every other use back to `wall`,
      -- which is what all of them were before: 40 is also the clerk's
      -- booth back panel (under the shelf rows 80/81 or under itself), and
      -- 40/76/77/90/91 all recur in INDIGO_PLATEAU_LOBBY, the ninth map on
      -- this id, where they draw the hall and the lift bank.
      --
      -- NEVER put 0 in an `above` set.  Map:tileAt does not answer nil off
      -- the top of a map -- it border-extends, so row 0 reads the map's
      -- borderBlock, which indoors is the black void block 0.  Listing 0
      -- to catch the Lobby's void-backed 90/91 fired the rule on every
      -- Mart's fridge row as well: row 0 dropped out of the bookcase run,
      -- the fridges came out 24px against the SALE cases' 32px, and their
      -- trim row stood as a separate box BEHIND the wall instead of on top
      -- of it.  Nothing can separate those two cases from above -- both
      -- see void -- so the Lobby (already out of scope here) gets the
      -- bookcase reading too, and the Marts come out right.
      when_above = {
        [40] = { { above = { 40, 80, 81, 83, 90, 91 }, class = "wall" } },
        [76] = { { above = { 74, 75 }, class = "wall" } },
        [77] = { { above = { 74, 75 }, class = "wall" } },
        [90] = { { above = { 17 }, class = "wall" } },
        [91] = { { above = { 27 }, class = "wall" } },
      },
      -- the clerk's counter, half a cell high like every service
      -- counter.  It is a C wrapping the alcove the clerk stands in: the
      -- south arm's drawn front (24/25) under its top band (8/56), the
      -- light work surface the east arm and the rest of the south arm
      -- share (16/41), and the north arm's end panel (89).  8 and 56 are
      -- the two halves of one top band -- the first pass read 8 as the
      -- cash register, pinned it `billboard`, and got a bare black
      -- outline standing on the counter with the tile's own art replaced
      -- by its neighbour's.
      -- ...and the register's own two tile rows (14/15 over 30/31) are
      -- part of that same work surface now that the machine has been cut
      -- off them as a sprite -- see `figures` below.
      counter = { 8, 14, 15, 16, 24, 25, 30, 31, 41, 56, 89 },
      -- the same potted plants as POKECENTER above -- MART shares that
      -- atlas, so this is the identical drawing tile for tile, and
      -- INDIGO_PLATEAU_LOBBY (the only map on this id that places it)
      -- puts four of them along the hall.  Across POKECENTER and MART
      -- all eight of these ids appear exactly 78 times each, which is
      -- exactly how often the 2x4 plant grid appears: they are never
      -- anything but this plant, so pinning them by tile cannot catch
      -- anything else.  Same reading as the POKECENTER entry: one
      -- organic silhouette in the THIN standee pool, per-pixel, 5
      -- voxels deep at its drawn 32px height, with the background
      -- shades named because the urn's foot lies flush on the block's
      -- bottom edge and votes the drawing's own darks away.
      prop = { 32, 33, 34, 35, 48, 49, 50, 51 },
      prop_bg = { { tiles = { 32, 33, 34, 35, 48, 49, 50, 51 },
                    shades = { "light", "white" } } },
      -- Left to the derived default on purpose: the floor checker and
      -- its shadowed variants (1/11/17/26/27/54) and the exit mat
      -- (12/28) all sit in cells the ROM marks walkable, so the cell
      -- rule lays them flat unaided.  (76/77, the SALE case's black
      -- interior, used to be left to the volume path here; it is now the
      -- back wall's third band, because a run of four rows has to be
      -- contiguous for the wall to collapse into one box at all.)
      -- THE CASH REGISTER: a till drawn across two tile rows in the middle
      -- of the counter's east arm, and the same drawing in all nine maps
      -- on this id (eight Marts plus the Indigo Plateau lobby), always at
      -- cell (1,5).  Like the Center's seated man it is drawn INTO the
      -- furniture, so it is cut out by the same authored mask, and for the
      -- same reason: no class pin can separate it from the counter,
      -- because the counter draws its own edging down columns 0 and 15 of
      -- the very same tiles.
      --
      -- That edging is what defeated every automatic reading. Black
      -- always survives the shade flood, so the standee pools extruded
      -- the two rules along with the machine and it stood flanked by a
      -- pair of tall black slabs; `console`'s keep-the-largest-drawing
      -- rule dropped them, but only by throwing away the receipt curl
      -- too whenever the flood happened to cut it loose.  The mask just
      -- says where the machine is: columns 2-13, plus the curl climbing
      -- to the top right, and the counter keeps its edging and its light
      -- work surface.
      --
      -- But it is a MACHINE, not a person, so unlike the seated man it
      -- carries a `depth` and stands as a solid rather than a sprite
      -- card.  A flat card of a till is exactly the billboard the standee
      -- pools exist to avoid -- it read as a decal on the counter, and
      -- turned edge-on with the camera.
      --
      -- AND IT IS NOT A BOX.  The 16x16 packs two facings, and the black
      -- linework says which is which: the keypad has its OWN complete
      -- border (cols 2-8, rows 4-11) sealed inside the outer silhouette,
      -- and what surrounds it is an L --
      --
      --     cols 2-----8 9--12
      --     +-----------+-----+  row 4
      --     |  keypad   | arm |    the L's upright arm: the printer and
      --     +-----------+-----+  row 11    display the paper feeds out of
      --     |   base / drawer  |  rows 12-15: the L's foot, drawn face-on
      --     +------------------+
      --
      -- So the keypad is NOT a face.  It is the machine's DECK seen from
      -- ABOVE -- the keys lie on it -- and `flat` lays it horizontal in
      -- the notch of the L, at the height the base band leaves it and
      -- with drawn row = depth row 1:1.  Extruding it instead stood that
      -- surface on end and painted the keys up the front of a plain box:
      -- the extruded-picture failure, and what the first pass shipped.
      --
      -- Everything else falls out of the drawing: the base band is 4 rows,
      -- so the deck stands 4 above the counter; the arm is 8, so it rises
      -- 8 above the deck; the paper reaches 4 more.
      --
      -- TWO AUTHORED NUMBERS.
      --
      -- `depth` 12, three quarters of the cell.  The keypad's own eight
      -- drawn rows measure 8, and at 8 the machine read thin on the
      -- counter, so the body runs half again deeper and the deck STRETCHES
      -- over it -- 8 rows into 12 voxels, centre-sampled, so every second
      -- row doubles and the keypad still covers the whole surface.  This
      -- is the one place in the model where a texel is not 1:1 with a
      -- drawn pixel; laying the panel 1:1 instead leaves a strip of the
      -- base band's top showing behind the keys.  The model is anchored at
      -- the counter cell's FRONT and grows north into the bare top behind
      -- it, so deepening it can never push the till toward the aisle: at
      -- 12 it still stops 4 voxels short of the cell's north edge.  This
      -- is the number to move if it wants more or less presence.
      --
      -- `thin`: 4 rows at 2.  Row 4 is the machine's
      -- own drawn top edge -- a black rule from column 3 to column 9 -- so
      -- everything above it is the receipt strip, and paper is 2 voxels
      -- like every other `cutout` here.  Centred in the body's band, so
      -- the strip leaves the arm's top face by a slot in the middle of it
      -- rather than flush with its front.  At the body's 8 the curl came
      -- out as a chunky wedge on the corner and stopped reading as paper.
      --
      -- `under` is 16/41 twice -- the plain work surface, which already
      -- carries the west edging (black over white) and the east (dark
      -- over black), so the counter closes up behind the machine with no
      -- synthesis at all.  The `counter` pin on 14/15/30/31 stays: the
      -- box under the till is still the counter, and the machine stands
      -- on its 8px top plane.
      figures = {
        {
          w = 2,
          depth = 12,
          thin = { rows = 4, depth = 2 },
          flat = { x = { 2, 8 }, rows = { 4, 11 } },
          tiles = { 14, 15,
                    30, 31 },
          under = { 16, 41,
                    16, 41 },
          pixels = {
            ".........XX.....",
            "........XXXX....",
            "........XXXXX...",
            "........XXXXXX..",
            "...XXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
          },
        },
      },
      -- NOT covered: INDIGO_PLATEAU_LOBBY, the ninth map on this id and
      -- the only one that is not the 4x4 shop.  It draws its own hall,
      -- lift bank and rope stanchions from tiles no Mart places, three
      -- of which fall in the engine's stale water set -- see
      -- reports/COUNTERS_pass2.md.  Pinning them is a tileset pass of
      -- its own and is deliberately not attempted here.
    },

    -- The route gates and their upstairs lounges, the four Underground
    -- Path entrance huts, the Safari Zone gate and its four rest houses
    -- -- twenty-five maps on one tileset.  (Viridian Forest's two gates
    -- draw the very same art from a SEPARATE id, FOREST_GATE below, and
    -- pins do not carry between ids.)  Before this entry every one of
    -- them was a swimming pool: 50/51 -- the dark panel the artist reuses
    -- as the wall's base course AND as every counter's front -- is one of
    -- the three ids (20/50/72, the $14/$32/$48 of the stale cache) that
    -- the engine's water set claims in every tileset, so the whole wall
    -- perimeter and every counter front recessed into a moat.  The other
    -- two are placed here as well: 20 is the exit doormat, 72 the top
    -- course of Route 2's wall.  What survived the water was towered
    -- instead -- the counters raised to a 16px slab, the cabinets boxed,
    -- the 2F window read as a 16-to-40px skyline, and the tables and
    -- binoculars flattened into the floor because their cells are
    -- walkable.
    GATE = {
      -- The wall band stays ONE 16px face.  Three wall drawings share
      -- it: the route gates' panelled course (32/33 -- its base course
      -- 50/51 is `counter`, see below), the
      -- Underground Path huts' and Route 22's plain stripes (0), and
      -- Route 2's speckled plaster (72 over its dark skirting 74).  0
      -- and 74 need no height correction but are pinned anyway, so the
      -- detector cannot swallow the corner plants into the band and
      -- tower them with it.  The gate 2F's big window is the same band
      -- two cells deep (58 glass, 45 its dither, 61 the diagonal glare,
      -- 62 the black mullions).  The door panes (41/43, the leaf drawn
      -- above the walkable threshold) are wall too, so a doorway reads
      -- as a recess in the band instead of a picture of a door lying on
      -- the floor -- the Center's warp-tile treatment, and pins are
      -- look-only so the cell stays walkable.
      --
      -- 50/51 is NOT in that list, and that is the one deliberate cost in
      -- this entry.  The artist draws one panel twice: as the wall cell's
      -- base course (32/33 over 50/51) and as the front of every counter
      -- (7/9/8 or 17/18 over 50/51).  A pin is per tile id and a class
      -- carries one height, so the two uses cannot be separated here at
      -- all -- only in `lib`, by letting a pin be conditional on the tile
      -- drawn ABOVE (see reports/COUNTERS_pass2.md).  Pinned `wall` (16)
      -- the band is one clean face and the counter the guard stands
      -- behind is a full 16px slab that hides him to the shoulders.
      -- Pinned `counter` (8) every counter is the half cell it is drawn
      -- as -- which is what the room is FOR -- and the price is that the
      -- wall cell's front 8px of depth drops with it: a shallow wall
      -- gains an 8px plinth (reads as a wainscot), and the deep margin
      -- masses that run two to eight cells north-south down the east and
      -- west sides of the fourteen maps that place both drawings (Routes
      -- 5/6/7/8, the five gate 1Fs, the Safari gate and its four rest
      -- houses) corrugate, their exposed flank stepping 16/8/16/8 every
      -- 8px of depth.  The other six -- Route 2, Route 22 and the four
      -- Underground Path huts -- place 50/51 and never 32/33, so they
      -- take the half cell for nothing.  The counters win where it costs:
      -- they are the object the player walks up to and talks over, they
      -- sit mid-room, and the margin masses are pure border filler seen
      -- edge-on.  This also puts GATE and FOREST_GATE on the same footing
      -- at last -- ROUTE_2_GATE draws the forest gates' room tile for
      -- tile and used to be the only one of the three with a 16px front.
      wall = { 0, 32, 33, 41, 43, 45, 58, 61, 62, 72, 74 },
      -- the counter, half a cell high everywhere it is drawn: its north
      -- rim and end caps (7/8), the long run between them (9), the top
      -- surface a counter drawn running north-south wears (23/24), and
      -- the drawn front panel (50/51) standing up as one clean 8px band
      -- with the surface riding the top face.  The guard leans on it
      -- instead of standing behind a wall stub, and a counter that runs
      -- wall to wall (Route 12's pair) matches one that ends in the open.
      counter = { 7, 8, 9, 23, 24, 50, 51 },
      -- 50/51 draws BOTH the counter's front and the wall's base course,
      -- and it is the bottom row of its cell either way -- so a flat pin
      -- has to pick one and be wrong about the other. Pinned `wall` the
      -- counters stood a full 16px; pinned `counter` the deep border
      -- banks corrugated 16/8 for sixteen rows and the room read as
      -- crates. What tells the two uses apart is what is drawn ABOVE:
      -- the wall stacks its panelled course (32/33) over the base, while
      -- a counter carries its own top (7/8/9). So the counter pin above
      -- is the default and this puts the wall back wherever the panel
      -- sits on top of it -- resolved per position, in TileShape.at.
      when_above = {
        [50] = { { above = { 32 }, class = "wall" } },
        [51] = { { above = { 33 }, class = "wall" } },
      },
      -- the tall glass-fronted cabinets: three shelf ranks (34/35)
      -- folded up a 24px box whose top face adopts the drawn top rim
      -- (7/8, pinned `counter` directly above it) through the mesher's
      -- authored-fold rule -- the HOUSE / Red's-house bookcase
      -- treatment.  Deliberately not `bookcase`: that collapses the
      -- drawing to one cell of depth, which would leave the wall cell
      -- behind each cabinet as bare floor, and its cap rule refuses a
      -- row pinned anything but `table`, so the cabinets would lose
      -- their tops as well.
      desk = { 34, 35 },
      -- standing per-pixel props with body, black-outline segmented: the
      -- little tables of the 2F lounges and the Safari rest houses (2/3
      -- the top, 18/19 the legs) and the 2F observation binoculars (36
      -- eyepieces, 52 barrels, 57 pedestal).  Both are drawn face-on
      -- with air between their legs and a clean white floor margin, so
      -- the standee segments whole -- and both were invisible before,
      -- flattened by the walkable-cell rule.  They stand on the floor:
      -- the window band is drawn ABOVE them, and the support rule only
      -- lifts a prop drawn above a box.
      billboard = { 2, 3, 18, 19, 36, 52, 57 },
      -- the plants, in the THIN pool like every other interior plant:
      -- the potted palm that stands in every hut and rest-house corner
      -- (5/6 crown, 21/22 fronds, 37/38 over 53/54 the pot), and Route
      -- 22's wall plant (14/15 crown, 30/31 pot), which stands on the
      -- half-cell planter its base course (50/51) makes -- a planter box
      -- now rather than the 16px pedestal it used to perch on.
      prop = { 5, 6, 14, 15, 21, 22, 30, 31, 37, 38, 53, 54 },
      -- the exit doormat (4 over 20): drawn from straight above, so it
      -- has to lie flat -- and 20 is the $14 water-fallback trap, which
      -- sank every gate's own doorway into a pond lip.
      ground = { 4, 20 },
      -- the flight up to a gate's 2F: real steps climbing east, the way
      -- the drawn treads rise to the right.  Pixel for pixel the same
      -- staircase as Red's house 1F, on the same four tile ids.
      stair_e = { 12, 13, 28, 29 },
      -- the flight down -- to 1F from a gate 2F, into the tunnel from an
      -- Underground Path hut: a sunken stairwell descending westward,
      -- high at the east lip where the player enters.  Again the same
      -- drawing and the same ids as Red's room upstairs.
      stair_down_w = { 10, 11, 26, 27 },
      -- Left to the derived default on purpose: the two floor checkers
      -- (1/17) and every threshold -- the door mats (55/56/94) and the
      -- tile under the door panels (42/59) -- sit in walkable cells, so
      -- the cell rule already lays them flat; and tile 16 is solid
      -- black, which the void rule flattens into exactly the darkness
      -- that should sit above Route 16's north wall.
    },

    -- Viridian Forest's north and south gates.  Tile for tile they are
    -- the same drawing as ROUTE_2_GATE, but they are their own tileset
    -- id, so they need their own copy of the pins.  These two maps never
    -- place the panelled wall course (32/33), so 50/51 is a counter
    -- front here and nothing else -- the half cell it is drawn as costs
    -- this id nothing at all, where GATE pays for it in the wall (see
    -- the note there).  Both ids run 50/51 `counter` now, so the three
    -- rooms that share this drawing -- the two forest gates and
    -- ROUTE_2_GATE -- finally match.  Before this entry the room was a
    -- pond with an island: 72 ($48) sank the north wall's top course, 50
    -- ($32) sank all four counter fronts, and 20 ($14) sank the exit
    -- doormat -- the three stale-cache water ids, all three placed in
    -- one small room.
    FOREST_GATE = {
      -- the wall band, one 16px face: the speckled plaster course (72)
      -- over its dark skirting (74), plus the door pane (41/43) drawn
      -- above the walkable threshold, so the doorway reads as a recess
      -- in the band rather than a door lying flat on the floor (pins are
      -- look-only; the cell stays walkable).  72 is the $48
      -- water-fallback trap and took the whole north wall down with it.
      wall = { 41, 43, 72, 74 },
      -- the four counters, half a cell high: end caps (7/8), the top
      -- surface running north-south (23/24), and the front panel (50/51)
      -- standing up as one clean 8px band with the surface riding the
      -- top face.  50 is the $32 water-fallback trap -- unpinned, every
      -- counter's front cell was a pond notch.
      counter = { 7, 8, 23, 24, 50, 51 },
      -- the potted palms down both side walls, three to a side, in the
      -- THIN standee pool like every other interior plant: 5/6 crown,
      -- 21/22 fronds, 37/38 over 53/54 the pot.  They stack with no gap
      -- between them, and each still segments as its own plant.
      prop = { 5, 6, 21, 22, 37, 38, 53, 54 },
      -- the exit doormat (4 over 20), drawn from straight above so it
      -- lies flat; 20 is the $14 water-fallback trap.
      ground = { 4, 20 },
      -- Left to the derived default on purpose: the two floor checkers
      -- (1/17) and the tile under the door panes (42/59) sit in walkable
      -- cells, so the cell rule already lays them flat.
    },

    -- Celadon's department store and the rooms that share its blockset:
    -- CELADON_MART_1F..5F and the ROOF, the two 2x2 lift cabins
    -- (CELADON_MART_ELEVATOR, SILPH_CO_ELEVATOR), ROCKET_HIDEOUT_ELEVATOR,
    -- the GAME_CORNER with its PRIZE_ROOM, and CELADON_DINER -- twelve
    -- maps off one atlas.  Everything the store owns was wrong: the
    -- U-shaped sales counters read their whole north-south arm as one
    -- drawing and towered to 48px (dragging the wall band they touch up
    -- with them), the merchandise racks fused sideways into 32px
    -- monoliths FOUR tiles deep -- the Poke Mart's failure exactly --
    -- the diner and roof stools sit in walkable cells and so flattened
    -- into the floor entirely, and three separate tiles fell into the
    -- engine's stale water set and sank into ponds indoors.
    LOBBY = {
      -- The two exit cells of every map (the sliding-door threshold, 4
      -- over 20).  20 is $14, which the stale-cache fallback counts as
      -- water in EVERY tileset, and rule 2 judges the whole CELL by it:
      -- both tiles of the doorway recessed into a pond lip just inside
      -- the shop door.  It is a flat mat, and the lift cabins use the
      -- same pair for their car door.
      ground = { 4, 20 },
      -- The wall band stays ONE 16px face.  The blank course (1) and the
      -- skirting course below it (33) are the band itself; everything
      -- else here is drawn BUILT INTO it at 16px, so wall height is the
      -- drawn height and each reads as a fitting jutting from the band
      -- rather than a tower:
      --   6/22    the framed notice beside the stairwell, every floor
      --   2/3/18/19   the pair of pay phones on 1F
      --   46/47   the floor-directory plaque (it also sits at the east
      --           end of 1F's counter top, where 16px reads as a sign
      --           board standing on the counter -- the one placement
      --           that is not wall, and the least bad of the two)
      --   62/63   the lift call-button panel in both 2x2 cabins
      --   72/73/88/89 the framed picture (72 is $48, a water-set id, so
      --           unpinned its top half sank)
      --   68/84   the roof's perimeter safety railing, drawn 16px tall
      --   75/76/77/78/79 the roof parapet and the Rocket lift's cabin
      --           walls (79 also rings the roof map as its border block);
      --           the Game Corner reuses 75/76/77/78 as the dark south
      --           end of its machine banks, where 16px reads as the
      --           bank's end cabinet
      --   91      the dithered wall course above the Prize Room counter
      --           and the roof stairhead
      --   92/93   the Rocket lift's horizontal cabin frame
      --   70/71   NOT wall panelling: the round tables' lower-left and
      --           lower-right rim ($46/$47).  They are here to lift the
      --           terrace and diner tabletops to the one height their
      --           middle can be built at -- see the long round-table
      --           note under `counter`.  The tileset places them in the
      --           two table blocks (29, 49) and nowhere else, so 16px
      --           costs nothing anywhere in the group.
      wall = { 1, 2, 3, 6, 18, 19, 22, 33, 46, 47,
               62, 63, 68, 70, 71, 72, 73, 75, 76, 77, 78, 79, 84,
               88, 89, 91, 92, 93 },
      -- 3F's television sets ($0E/$0F/$1E/$1F): the one drawing in this
      -- tileset that is a deliberate object with a body -- a black-framed
      -- cabinet, a bezel and a lit screen, drawn face-on -- and the same
      -- thing Red's living room stands up.  Six placements: four on the
      -- two goods counters, two against the east wall band.  As `wall`
      -- each was a 16px CUBE with the TV art folded onto one face, so the
      -- counters wore grey filing cabinets and the TV shop read as a
      -- stockroom.  The standee pool cuts the drawing per pixel at 10
      -- voxels of body instead, and the support rule does the rest: the
      -- four counter sets are drawn directly above an authored 8px
      -- `counter` row, so they STAND ON the counter and the tiles they
      -- claim keep rendering as counter top rather than holing it.  (The
      -- art carries a full black frame with light margin inside it, so
      -- the segmentation flood has nothing to drain and the whole set
      -- survives.)  Its own pool, away from `stool`, so a TV never stacks
      -- with a chair drawn beside it.
      billboard = { 14, 15, 30, 31 },
      -- Every service counter in the group, half a cell high like the
      -- Center's and the Mart's.  One 8px band means the drawn front row
      -- stands up and everything above it rides the TOP face in drawn
      -- order -- which is what a counter arm running north-south IS: the
      -- rows above the front are its top surface seen from above, not
      -- height.  Unpinned the arms measured their full 7-row run and
      -- towered to 48px, taking the wall band they touch with them.
      --   38/39/41    the top surface and its end caps
      --   21/48/49    the south front panel and its end caps
      --   54/57       the arms' left and right side edges
      --   36/37/52/53 the games console and its controller laid out on
      --               3F's counter.  This is pixel for pixel the drawing
      --               Red's house pins `relief` -- a prop seen from
      --               ABOVE -- and `relief` is the class it wants.  It
      --               cannot have it here: Structures.buildRelief anchors
      --               its extrusion at y=0 and has no support lookup,
      --               while every placement of this drawing in the
      --               tileset is on a counter TOP.  Pinned `relief` the
      --               cell is claimed, dropped to floor level and punched
      --               a 16x16 hole clean through the counter (verified
      --               in-engine, pass-2 report).  `counter` leaves the
      --               console exactly where relief would put it -- flat,
      --               flush with the surface, art on the top face, drawn
      --               once -- and gives up only relief's three voxels of
      --               lift.  The report carries the one-place engine
      --               change that would free it.
      --   9/25/85/86/87  the round tables of the diner and the roof
      --               terrace: their north rim (9/25 = $09/$19) and the
      --               pedestal course at the south (85/86/87).
      --
      -- THE ROUND TABLES in full, because the shape is a compromise.  The
      -- drawing (block 29, and the same four rows split across blocks 45
      -- and 49 in the diner) is
      --      $09 $27 $27 $19      an octagonal top seen from above, with
      --      $36 $37 $37 $39      a pedestal drawn below its southern
      --      $46 $37 $37 $47      rim
      --      $55 $56 $57 $37
      -- Its four INTERIOR tiles are $37, which is ALSO the light half of
      -- the checkerboard floor and the plain upper wall of the Prize Room
      -- and the roof stairhead, so $37 cannot be pinned at all (see the
      -- closing note).  Left to the detector those four are a two-row
      -- column, which buildVolume reads as a repeat, floors at unit 2 and
      -- builds at 16px -- and with the whole rim pinned `counter` at 8px
      -- the terrace tables came out as grey CUBES sitting on trays.
      --
      -- So stop fighting the 16px and let it BE the tabletop: 70/71
      -- ($46/$47, the lower-left and lower-right rim) move to `wall`, and
      -- the table's whole front course then stands at the same 16px its
      -- middle already does -- one flat disc, the drawn octagon on its
      -- top face and the lower arc folded down its front.  What stays at
      -- 8px is the FAR rim (9/25, and the shared 39/54/57) and the
      -- pedestal (85/86/87): the far rim is occluded by the 16px top in
      -- front of it, and the pedestal is meant to sit low.  16px is also
      -- the right height against the 8px `stool` chairs drawn around it
      -- -- a terrace table you sit at, not a footstool.
      counter = { 9, 21, 25, 36, 37, 38, 39, 41, 48, 49, 52, 53, 54,
                  57, 85, 86, 87 },
      -- Free-standing merchandise racks and glass cases: TALL drawings,
      -- not deep ones.  The four-row rack (42-45 / 58-61 / 64-67 /
      -- 80-83) stands two racks abreast on floors 2F-5F and along the
      -- Game Corner's north wall, and the detector boxed each pair into
      -- ONE 32px slab four tiles deep -- the Poke Mart's exact failure.
      -- A bookcase rank collapses onto a one-cell-deep box at the full
      -- drawn height instead, and the back rows become hidden floor, so
      -- racks standing side by side stay separate objects with an aisle
      -- behind them.
      -- 34/35/50/51 is the glass display case / vending machine, which
      -- the same rule fits at BOTH its drawn sizes: 16px where it wears
      -- the 1F phones or the 3F TV above it, 24px where a counter cap
      -- (38/41) tops it on the roof, the Prize Room and the Game
      -- Corner.  50 is $32, a water-set id, so every one of these cases
      -- stood in a pond before it was pinned.
      bookcase = { 34, 35, 42, 43, 44, 45, 50, 51, 58, 59, 60, 61,
                   64, 65, 66, 67, 80, 81, 82, 83 },
      -- The stools: the diner's chairs, the roof terrace's, the six
      -- rows in front of the Game Corner's machine banks and the four
      -- on 1F.  Their cell's bottom-left tile is 23 ($17), which IS on
      -- the tileset's walkable list, so rule 3 resolved every one of
      -- them to flat ground and they vanished into the floor
      -- completely.  A pin is the only thing that overrides that.  The
      -- drawing carries a full black outline with the floor dither
      -- showing at all four corners, so the standee segments cleanly --
      -- and `stool` keeps its own pool, apart from anything it touches.
      stool = { 7, 8, 23, 24 },
      -- Deliberately NOT pinned:
      --   $37 (55) is three different things -- the light half of the
      --     checkerboard floor, the interior of the round tables, and
      --     the plain upper wall of the Prize Room and the roof
      --     stairhead -- and every class that suits one ruins the
      --     others: `ground` holes the wall and the tabletop, `counter`
      --     turns every second floor tile into an 8px lump, `wall` turns
      --     it into a 16px pillar.  The cell rules already answer the
      --     floor (its cells are walkable through their $45 bottom-left
      --     tile) and the wall (its cells are not), and the tabletop is
      --     answered above by raising 70/71 to meet the 16px the
      --     detector builds there.  Left unpinned on purpose.
      --   $10 (16) is pure black and the void rule already flattens it
      --     to the interior darkness above the Game Corner's wall.
      --   The stair openings (10/11/26/27, 40/56) and the lift doors
      --     (12/13/28/29) all sit in WALKABLE cells and fold into the
      --     facade on their own, which is what the doorway fold is for.
      --   $20/$45 (32/69) are the two floors and are walkable.
    },

    -- Pewter's museum, both floors (the tileset shares the gates' atlas
    -- image but is its own id).  The exhibits were the worst case in the
    -- whole building: 50 is $32, a water-set id, and it is the base row
    -- of EVERY display case, so rule 2 judged each case's bottom cell
    -- water and sank the fossil vitrines, the space shuttle and the
    -- glass cabinets into ponds.  72 is $48 and is the wall band's upper
    -- course, so the north wall recessed too -- leaving its lower course
    -- alone as an 8px stub.  On top of that the benches sat in walkable
    -- cells and flattened away, the corner plants towered to 32px, and
    -- both staircases (also walkable) were flat floor.
    MUSEUM = {
      -- the two street doors on 1F: the same $14 mat trap as the
      -- department store's, flat
      ground = { 4, 20 },
      -- the wall band as one 16px face: the dithered upper course (72,
      -- the $48 water-set id) over the skirting course (74), and the
      -- two framed paintings hung in it (78/79)
      wall = { 72, 74, 78, 79 },
      -- The low partitions that divide both floors -- the tileset's own
      -- counterTiles name 23 ($17) -- drawn exactly like the department
      -- store's counter arms: a light top surface seen from above with
      -- dark side edges.  Half a cell, so they read as barriers you see
      -- over rather than interior walls.  Their north caps and their
      -- south base rows belong to the case group below, at the same 8px.
      counter = { 23, 24 },
      -- Every vitrine in the museum, as tall drawings one cell deep:
      --   7/8/34/35   the run of eight glass cabinets along 1F's north
      --               wall (7/8 is the cabinet's top surface, so the
      --               rank wears it as its top face -- which is why it
      --               is here and not in `counter` with the partitions
      --               whose north cap it also draws)
      --   9/50/51     the low case at 1F's centre (9 the top surface,
      --               50/51 the base panels) and the base row under the
      --               partition ends
      --   25/39/40/44/46/48/49/58/60/63/70/71/83  the fossil vitrine,
      --               four drawn rows inside one black frame: the dark
      --               top surface, the ammonite specimens on their
      --               light bed, the placard, and the base.  Two on 1F,
      --               one on 2F.  Collapsed to one cell of depth it
      --               stands as a 32px case instead of a 16px lid
      --               floating over a pond.
      --   64-69/80-91 the space-shuttle vitrine on 2F, the same drawing
      --               shape three cells wide.
      -- 50/51 is $32/$33 -- the water-set id that sank all of them.
      bookcase = { 7, 8, 9, 25, 34, 35, 39, 40, 44, 46, 48, 49, 50,
                   51, 58, 60, 63, 64, 65, 66, 67, 68, 69, 70, 71,
                   80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91 },
      -- the visitors' benches on 1F: their cell's bottom-left tile is
      -- 18 ($12), which is on the walkable list, so they resolved to
      -- flat ground and disappeared.  Seat-height standees in their own
      -- pool, like the department store's stools
      stool = { 2, 3, 18, 19 },
      -- the corner potted plants (crown 5/6/21/22, pot 37/38/53/54):
      -- the THIN standee pool, like every other interior plant in this
      -- profile.  Unpinned they were a 32px two-cell tower.
      prop = { 5, 6, 21, 22, 37, 38, 53, 54 },
      -- the Old Amber in its rounded case, drawn face-on with a clean
      -- black outline and a light margin at every corner: the standee
      -- with body, segmented so the backing floods away and the amber
      -- inside the outline stays
      billboard = { 76, 77, 92, 93 },
      -- 1F's staircase UP to 2F: a real rising flight climbing east,
      -- the way the treads are drawn (low at the west, high at the
      -- east).  Its cell is walkable, so without the pin it was flat
      -- floor with the stair art painted on it.
      stair_e = { 12, 13, 28, 29 },
      -- 2F's staircase DOWN to 1F: the same flight from above, so it
      -- descends westward -- the player steps on at the east lip.  Same
      -- tile ids Red's bedroom uses for its stairwell, which is the
      -- convention across Gen 1's interior blocksets.
      stair_down_w = { 10, 11, 26, 27 },
      -- Deliberately NOT pinned: 1 and 17 ($01/$11), the two halves of
      -- the checkerboard floor.  Every floor cell's bottom-left tile is
      -- $01, which is walkable, so the cell rule already makes the whole
      -- cell flat ground.
    },

    -- Cinnabar Lab and its three side rooms (trade, metronome, fossil),
    -- the Fuchsia Warden's house, the Fuchsia meeting room and the Safari
    -- Zone's secret house -- seven maps on one tileset.  Every indoor
    -- failure mode shows up here at once: the detector raised the machine
    -- banks as 32px monoliths TWO cells deep, boxed the free-standing
    -- shelf racks the same way (and CAPPED the metronome room's racks at
    -- 16px because their book rows repeat, so a 32px shelf came out a
    -- 4-tile-deep 16px slab), cut every lab bench into a patchwork of
    -- 8/16/32px stubs, flattened the chairs into floor, merged the
    -- meeting room's long partition with the corner plants into a 48px
    -- tower -- and dropped six tile ids into the engine's stale-cache
    -- water set, so the bench tops ($04/$05/$14/$15), the table's monitor
    -- ($48) and the Warden's round specimens ($32) recessed into pond
    -- lips inside the building.  Oak's Lab (the DOJO entry) is the
    -- reference: same rooms, same answers.
    LAB = {
      -- the wall band stays one 16px face.  Blank courses ($22), the
      -- pillar/corner that turns Cinnabar Lab's L ($23), the framed
      -- Pokeball picture (16/17/32/33), the metronome room's row of
      -- wall brackets (48/49 -- drawn INTO a band that is two cells
      -- deep there, so both cell rows stay one 16px face), the vent
      -- panel over Cinnabar Lab's three doorways (24/25), and the low
      -- dark base course with its end caps (42/43) that the meeting
      -- room's partition and the Warden's machine both stand on.
      -- The Warden's big machine (87/88/89 top, 28/71/29 the dial row,
      -- 36/37 the grille row, over 24/25 and the 42-34-34-43 base) is
      -- ALSO wall: it is drawn 32px tall and free-standing, so a
      -- `bookcase` would be the honest shape -- but its grille tiles
      -- 24/25 are the very tiles Cinnabar Lab hangs in its wall band
      -- above the doors, and its base row is the shared $22 band, so no
      -- per-tile pin can make it 32px without either stubbing the Lab's
      -- wall panel or splitting the machine into columns of different
      -- heights.  One clean 16px console beats both.
      wall = { 16, 17, 24, 25, 28, 29, 32, 33, 34, 35, 36, 37,
               42, 43, 48, 49, 71, 87, 88, 89 },
      -- the equipment banks and the shelf racks: TALL drawings, not deep
      -- ones.  Each rank collapses onto a ONE-CELL-DEEP box at its full
      -- drawn height and its back rows become hidden floor -- the
      -- Dojo/Mart treatment, and the only thing that stops the fossil
      -- room's and the secret house's machine walls from being 32px
      -- blocks two cells thick.  69/70 + 85/86 are the cabinet tops,
      -- 10/11 the dial faces, 74/75 + 90/91 the narrow filler columns,
      -- 26/27 the plinth with its feet, 59 the black end pilaster;
      -- 40/41 are the metronome room's and the meeting room's shelf
      -- ranks.
      --
      -- 64/65/66 -- the TOP-TRIM row (one black line, one white
      -- highlight, then grey) that every flat-topped unit in this
      -- tileset wears -- are here too, and this is the load-bearing
      -- decision in the entry.  They used to be `table`.  A `table` is
      -- an authored upright BOX, and the support rule stands a pinned
      -- standee drawn directly above an authored box ON it: every chair
      -- on the FAR side of a table in this tileset is drawn directly
      -- above that table's trim row, so the trade room's two north
      -- chairs and the meeting room's spare chair were lifted onto the
      -- tabletops -- and their cells were re-tiled as tabletop, marching
      -- each table two tile rows north to meet them.  A `bookcase` is
      -- authored but is NOT a box (its art mode is the rank collapse),
      -- so the support rule does not fire and those three chairs stand
      -- on the floor where they are drawn.
      -- Nothing else about the trim changes for the worse.  Where it
      -- caps a shelf rank (64/66 over 40/41 or 10/11, in the metronome
      -- room, the meeting room, the fossil room and the secret house)
      -- it simply becomes the rank's fourth row: the same 32px height
      -- and the same top-face art the cap-adoption rule used to hand it,
      -- minus the 12px stub the trim used to render as BEHIND the shelf.
      -- Where it tops a table or the Warden's bench it becomes that
      -- unit's own 8px back rim, tucked behind the 12px top.
      -- (The one thing it costs is named in the report: the meeting
      -- room's two partitions used to hand this trim to the 16px band's
      -- TOP face -- the mesher gives a full-height course the authored
      -- UPRIGHT row above it -- and now top with their own band art.)
      bookcase = { 10, 11, 26, 27, 40, 41, 59, 64, 65, 66, 69, 70,
                   74, 75, 85, 86, 90, 91 },
      -- the lab furniture, at table height.  The benches in the fossil
      -- and metronome rooms (2/3 the specimen tray, 4/5 + 20/21 the
      -- microscope, 18/19 the tray's rack row) and the big lab tables
      -- (80/81/82 the top, 83/58/84 the front rail and its legs).
      -- 72/73 -- the monitor and the ball lying on the table -- ride the
      -- table's authored height rather than standing as separate
      -- cutouts, exactly as Oak's starter balls do; pinning them also
      -- stops the display frame's black corner brackets from
      -- auto-extracting into standing prisms.  Four of these ids
      -- ($04/$05/$14/$15) plus $48 are the tileset's water-fallback
      -- traps: unpinned they sink into a pond lip in the middle of the
      -- room.  With the trim row moved to `bookcase` the top face of
      -- each table now wears its own drawn surface instead of the trim
      -- -- which is how the Warden's bench finally shows the monitor and
      -- the Pokeball the artist drew on it.
      table = { 2, 3, 4, 5, 18, 19, 20, 21, 58, 72, 73,
                80, 81, 82, 83, 84 },
      -- seats, the 8px standee pool, all of them in WALKABLE cells and
      -- therefore flat floor until pinned: the four chairs round the
      -- trade room's table and the meeting room's spare (14/15/30/31,
      -- a whole cell each) and the little stool tucked under every lab
      -- bench (6/7 its top edge, 22/23 its seat and legs).  6/7 also
      -- carry the bench's apron along their top edge -- the standee
      -- wears a thin dark cap for it, which is cheaper than dropping
      -- the stool to a half-cell drawing with no floor margin.
      -- The chairs on the far side of a table stay on the FLOOR only
      -- because the trim row above them is no longer a box; see the
      -- bookcase group.
      stool = { 6, 7, 14, 15, 22, 23, 30, 31 },
      -- the tall corner plants: two cells of drawing (44/45 + 60/61 the
      -- frond crown, 46/47 + 62/63 the stem and pot), mostly silhouette,
      -- so the THIN standee pool -- as in every other interior.  The
      -- detector had them at 0/8/16/24/32px depending on which corner
      -- they stood in, and in the meeting room it fused them into the
      -- partition and towered the pair to 48px.
      prop = { 44, 45, 46, 47, 60, 61, 62, 63 },
      -- the five round specimens in the Warden's house: one 16x16 cell
      -- each, drawn ROUND with a dithered shell and a lit underside.
      -- Neither a box nor a flat cutout reads them; the round archetype
      -- carves a voxel ball per cell from the drawing's darkest-pixel
      -- outline, which is what they are.  50 is a water-fallback trap,
      -- so unpinned the row sat in five pond lips.
      cylinder = { 50, 51, 67, 68 },
      -- Deliberately NOT pinned: the checker floor (1/38) and the fossil
      -- room's striped carpet (12/13) are walkable cells and already
      -- flat; the doormat (39/55) likewise; the three doorways
      -- (76/77 over 52/53) are walkable and the engine folds them into
      -- the facade; Cinnabar Lab's black surround (54) is authored void
      -- by the void rule; and the bench aprons 8/9 stay flat floor,
      -- which is where the artist drew them -- inside the walkable cell
      -- in front of the bench.
    },

    -- Celadon Mansion's three floors and its roof, plus the Celadon
    -- chief's house -- five maps on one tileset.  The mansion maps are
    -- half interior and half OUTSIDE: the east third of every floor is
    -- the open-air stair landing, so the entry has to keep an outdoor
    -- strip flat while it furnishes the rooms.  The detector towered the
    -- display cabinets, boxed the potted palms into 32px 4-tile-deep
    -- monoliths, raised the 2F larder cabinet as a 48px tower taller than
    -- the walls, gave the same wall band three different heights
    -- (8/16/48) on one map -- and sank the whole cabinet bank AND both
    -- front-door mats into pond lips, because nine tile ids here
    -- ($04/$14/$22/$23/$32/$33/$38/$48/$57) sit in the engine's
    -- stale-cache water set.
    MANSION = {
      -- one 16px face for every wall course, indoors and out: the rooms'
      -- north band (80), the interior partition (30) with its white top
      -- rim (76/77), the doorway lintel over the front door (22/23), the
      -- east exterior wall the landing runs along (74/75) with its
      -- junction pieces (72/73 -- 72 is a water trap -- and 88/89), the
      -- band's feet and corners (90/91/92/93), and the roof's own rim
      -- and corner blocks (78/79).  The roof parapet railing (15 over
      -- 31, with end caps 42/43 and 33/49) is drawn a full 16px tall, so
      -- it stays in the same band rather than dropping to `fence`: on an
      -- open roof a knee-high rail reads as a kerb.  48 and 6/7 are the
      -- rooftop shed's base course.
      wall = { 6, 7, 15, 22, 23, 30, 31, 33, 42, 43, 48, 49, 72, 73,
               74, 75, 76, 77, 78, 79, 80, 88, 89, 90, 91, 92, 93 },
      -- the display cabinets along the north wall of 1F and the chief's
      -- house: TALL drawings, not deep ones, so each rank collapses onto
      -- a one-cell-deep box at its drawn height.  34/35 are the shelf
      -- row of the short cabinets, 40/21 + 56/87 the two rows of the
      -- tall ones (the pair with the trophy in the glass), 50/51 the
      -- plinth.  Their top row is 38/41, pinned `table` below because
      -- the mansion's big tables wear the same trim -- the bookcase
      -- builder adopts it as the rank's CAP, which lands the short
      -- cabinets at 24px and the tall ones at 32px, exactly their drawn
      -- heights.  45/46 + 61/62 + 63/47 is 2F's larder cabinet, four
      -- drawn rows standing free of any wall: 32px and one cell deep
      -- instead of the 48px tower the detector built.
      -- Six of these ids are water-fallback traps ($22/$23/$32/$33/$38
      -- /$57) -- the whole cabinet bank was a pond.
      bookcase = { 21, 34, 35, 40, 45, 46, 47, 50, 51, 56, 61, 62, 63,
                   87 },
      -- table height.  The long tables in 1F and the chief's house
      -- (38/39/41 top edge, 54/55/57 body, 60/58/59 the front rail with
      -- its two legs) and the writing desks on 2F and 3F (36/37/52/53
      -- the back edge with the papers and the ball on it, 64/65/66/67
      -- the body).  The desks' aprons (2/3/85/86 over 18/19) are drawn
      -- into the WALKABLE cell in front and stay flat floor, which is
      -- how the artist placed them.
      -- Known compromise: the rooftop shed on CELADON_MANSION_ROOF is
      -- drawn with the table's own top and body tiles (38/39/41 over
      -- five rows of 54/55/57) with a door punched in its base, so it
      -- comes out a 12px block rather than a shed.  Nothing towers there
      -- any more -- the detector had its east columns at 48px -- and no
      -- per-tile pin can give one drawing two heights.
      table = { 36, 37, 38, 39, 41, 52, 53, 54, 55, 57, 58, 59, 60,
                64, 65, 66, 67 },
      -- the stool at the 2F/3F desk: a whole cell of drawing (2/3 over
      -- 18/19) sitting in a WALKABLE cell, so flat floor until pinned.
      -- The 8px standee pool, seat height, as in Red's rooms.
      stool = { 2, 3, 18, 19 },
      -- the potted palms: two cells of drawing (68/69 crown, 8/9 fronds,
      -- 70/71 stem, 24/25 pot), mostly silhouette, so the THIN standee
      -- pool -- the same numbers the generic HOUSE entry uses, and the
      -- same answer every interior plant gets.  The detector had them as
      -- 32px boxes four tiles deep.
      prop = { 8, 9, 24, 25, 68, 69, 70, 71 },
      -- the front-door mats of 1F and the chief's house.  Their bottom
      -- tile is $14, which the engine's stale-cache fallback counts as
      -- water in every tileset, so the mat -- and the whole cell with it
      -- -- recessed into a pond lip just inside the door.  It is a flat
      -- rug on the floor.
      ground = { 4, 20 },
      -- Deliberately NOT pinned: the interior checker floor (17), the
      -- landing's open-air ground (1), the black surround (16, authored
      -- void), the back and rooftop doors (81-84, walkable and folded
      -- into their facade), the desk aprons (85/86), and the landing
      -- edge (5).
      -- CANNOT be pinned, engine-side: the four staircases (12/13/28/29
      -- the rising flight, 10/11/26/27 the sunken one) are in this
      -- tileset's doorTiles, and Structures' door fold OVERWRITES the
      -- resolved shape of any door cell whose north neighbour is upright
      -- -- without checking `authored` -- so a stair_e / stair_down_w pin
      -- is silently discarded.  The indoor flights therefore read as
      -- doorways folded into the north wall band, which is at least what
      -- they are (you walk into them from the room).  The roof's two
      -- flights, which stand clear of any wall, come out as a shallow
      -- 8px lip -- a stairwell mouth, near enough -- and pinning them
      -- `wall` would be worse: it would plug the openings with a 16px
      -- block in the middle of the roof.  See the report.
    },

    -- Silph Co's 11th floor (the president's office), Bill's house and
    -- the Pokemon Fan Club -- three rooms that share one tileset and
    -- almost no furniture.  The detector raised Silph's side walls as
    -- 48px towers (the drawn band is three cell rows deep, so it
    -- measured the whole column), split the Fan Club's wall band across
    -- 0/8/16px AND a pond lip, boxed Bill's two transporter drums into
    -- 48px slabs five tiles deep, and left every chair flat because they
    -- sit in walkable cells.  Six ids here ($14/$1F/$32/$34/$40/$48) sit
    -- in the engine's stale-cache water set -- including $1F, the main
    -- FLOOR tile, which sank wherever it shared a cell with $48.
    INTERIOR = {
      -- the wall band, one 16px face throughout: the rooms' face-on
      -- courses (52 upper, 68 lower; 16 in Bill's house and Silph's
      -- outer band), the courses seen from above along the south and the
      -- partitions (87 top, 88 bottom), the side walls (89/90), the end
      -- caps and junction blocks (45/46), the framed Pokemon portraits
      -- hung in the band (19/20 over 35/36), and the padded bench built
      -- into the Fan Club's north wall (49/50/51 -- its lower half,
      -- 65/66/67, is drawn into the walkable cell in front and stays
      -- flat, the way the artist drew it).
      -- 93/94 are Silph's CARD KEY door: the block only exists while the
      -- door is locked (data.field.cardKey swaps it out), so it never
      -- appears in maps.lua -- but the probe sees it, and unpinned it
      -- came out 0px/8px in the middle of a 16px wall.
      -- Bill's pipework belongs here too: the stubs either side of each
      -- drum (32/48, 37/53) and the run between them (38/54), all drawn
      -- 16px tall against the band.
      wall = { 16, 19, 20, 32, 35, 36, 37, 38, 45, 46, 48, 49, 50, 51,
               52, 53, 54, 68, 87, 88, 89, 90, 93, 94 },
      -- Bill's two transporter drums: a TALL drawing (four rows of
      -- cylinder plus a base course), not a deep one.  The bookcase
      -- collapse gives each drum one cell of depth at its full 32px
      -- height instead of the 48px, five-tile-deep slab the detector
      -- built, and its top face wears the drum's own lid.  7/8/9/10 is
      -- the lid, 23/24/25/26 and 39/40/41/42 the barrel, 55/56/57/58 the
      -- footing.
      bookcase = { 7, 8, 9, 10, 23, 24, 25, 26, 39, 40, 41, 42,
                   55, 56, 57, 58 },
      -- ...and the drums are the reason this tileset turns the shelf
      -- relief OFF: the collapse here is borrowed for a MACHINE, whose
      -- light regions are the barrel's own lit face and not panes
      -- behind a frame.  Sinking them would dent the drum.
      bookcase_relief = false,
      -- The big OCTAGONAL boardroom table -- the Fan Club's and Silph
      -- 11F's, the same drawing in both -- half a cell high, and half a
      -- cell on purpose.  A `counter` is ONE band: exactly the drawing's
      -- bottom row stands up as the front and every row above it rides
      -- the top face IN DRAWN ORDER.  For a table drawn in PLAN that is
      -- the only class that reproduces the plan; a taller box wears its
      -- NORTH row's art across the whole top face and smears it.
      --
      -- The octagon itself is cut at TILE granularity, which is the
      -- finest the mesher has: an authored tile is its own 8x8 column,
      -- so the bevel is drawn by choosing which tiles rise.  Reading the
      -- Fan Club rows (Silph is the identical shape eight rows further
      -- down the map):
      --   row 4        72 74 74 74 74 73         6 tiles wide
      --   rows 5-8   72 <----- 8 tiles -----> 73  8 tiles wide
      --   row 9        63 64 64 64 64 81         6 tiles wide
      --   row 10          75 76 76 75            4 tiles wide
      -- 72/73 are the north chamfer, 63/81 the south one, 77/78 the
      -- straight flanks, 74 the north rim and 64 the top itself.  75/76
      -- -- the front apron with its two drawn legs -- is pinned so the
      -- octagon's south edge closes and the legs stand on the front face
      -- instead of lying painted on the floor; it sits in the walkable
      -- cell in front of the table, which is the cell a player stands in
      -- to talk across it, and an 8px apron there reads as standing AT
      -- the table (the same arrangement as the Center's counter).
      -- 79 and 82, the OUTER corner of the south bevel, are `ground` --
      -- see the ground group.
      --
      -- 91/92, the statue's pedestal, ride the top face here rather than
      -- standing with the statue: those two ids are ALSO the wall band's
      -- base blocks where a side wall meets the south course in Silph,
      -- so six tiles at the foot of Silph's walls sit 8px instead of
      -- 16px.  It is a notch at the foot of a wall the player never
      -- faces, and the alternatives are worse in both directions -- a
      -- 16px stub standing in the middle of the boardroom table, or a
      -- paper cutout standing at the foot of every south wall.
      -- 40 and 48 are water-fallback traps: unpinned, the table's whole
      -- north-west cell was a pond, and it dragged the floor tile $1F
      -- sharing that cell down with it.
      counter = { 63, 64, 72, 73, 74, 75, 76, 77, 78, 81, 91, 92 },
      -- The Pokemon statue standing in the middle of both boardroom
      -- tables: a per-pixel cutout, ONE voxel deep, standing ON the
      -- table through the authored-box support rule -- a standee drawn
      -- directly above an authored box rises from that box's top, which
      -- is how the gym's bird statues stand on their plinths and the
      -- potted plant stands on Red's table.  17/18 is the crown and the
      -- head, 33/34 the face and the top rim of the pedestal it stands
      -- in; the pedestal proper (91/92) stays `counter` under its feet.
      -- The four claimed tiles keep rendering as the tabletop they were
      -- cut out of, so the table is whole underneath.
      -- `cutout` and not `prop`: the drawing has NO floor margin -- it
      -- is surrounded on all four sides by the tabletop's own mid grey
      -- -- and the cutout pool's stricter contract makes mid shades
      -- background unconditionally, so the tabletop drains away cleanly
      -- while the black outline, the paint whites and everything they
      -- enclose survive.  Pinned `counter` with the rest of the table
      -- (what it was) the statue was painted FLAT on the tabletop.
      cutout = { 17, 18, 33, 34 },
      -- Bill's desk and the Silph president's, at table height: 11-14
      -- the surface with the terminal and the ball on it, 27-30 the
      -- front edge.  Their aprons (43/44 + 91/92 on the row below) are
      -- drawn into the WALKABLE cell in front; 43/44 belong to the stool
      -- there, not to the desk.
      table = { 11, 12, 13, 14, 27, 28, 29, 30 },
      -- and those eight ids are the ONLY `table` in this tileset, so the
      -- height override is this desk's alone: 8px, the height its apron
      -- is drawn and the plane the `bills_desk` template stands its top
      -- on (see `buildings` below).  The pin is only the degradation
      -- path here -- the template claims both placements -- but the two
      -- must not disagree about where the desk's top is.
      --
      -- `stool` is 5 for the same reason: that is the drawn elevation of
      -- BOTH seats in this tileset -- rows 11-15, the seat's front edge
      -- over its legs -- and the height the `club_stool` template stands
      -- them.  Bill's chair and the Fan Club's are different drawings
      -- above the seat but share tiles 59/60 below it, so they are drawn
      -- at the same height pixel for pixel; the class default of 8 was
      -- three voxels over both.  Every one of these cells is WALKABLE,
      -- so this is also where a character sitting on one ends up.
      heights = { table = 8, stool = 5 },
      -- the seats: Bill's desk stool (43/44 over 59/60) and the Fan
      -- Club's four members' chairs (61/62 over 59/60), a whole cell
      -- each.  All of them sit in WALKABLE cells, so they were flat
      -- floor until pinned; the standee pool puts them at seat height,
      -- which is also where a character standing on the cell ends up.
      -- The Fan Club's four are modelled in full by `club_stool` below
      -- and these pins are their degradation path; Bill's chair stays a
      -- standee, stood up as a part of `bills_desk`.
      stool = { 43, 44, 59, 60, 61, 62 },
      -- flat, and pinned flat on purpose.  31 is the rooms' floor tile
      -- and needs no pin for its 980 walkable placements -- but the
      -- water test runs per CELL on the engine's own stale set, BEFORE
      -- any neighbouring pin can help, so the floor tiles sharing the
      -- Fan Club's and Silph's north-west table cell with $48 sank into
      -- the pond with it.  A pin is the only rule that outranks it.
      -- 1/2 are the curve of Bill's drums where they meet the floor,
      -- drawn below the pinned barrel and flat where they lie.
      -- 79/82 are the OUTER corner of the octagon's south bevel, one
      -- tile beyond 63/81 on each side.  Raised with the rest of the
      -- table they squared both bottom corners off and left an 8px stub
      -- standing in the floor a tile away from the table on each side;
      -- flat they are what they are drawn as -- the table's cast shadow
      -- where the bevel meets the floor -- and the octagon closes with a
      -- clean 45 degree step on all four corners.
      ground = { 1, 2, 31, 79, 82 },
      -- Deliberately NOT pinned: the doormats (70/71) and Silph's warp
      -- pads, stairwells and elevator mouth (3/4, 5/6/21/22, 83-86) are
      -- walkable and already flat; 47 is the black surround outside the
      -- building's footprint and the void rule authors it; 69 is the
      -- shadow course under Bill's drums, drawn into a walkable cell and
      -- correct flat.
    },

    -- The Cable Club rooms and the Bike Shop (one tileset, three maps).
    -- COLOSSEUM and TRADE_CENTER are the same 5x4 room with a different
    -- machine in the middle and a different board on the wall; BIKE_SHOP
    -- reuses the same wall, floor and counter for a showroom full of
    -- bicycles.  Between them the three maps place every tile.
    --
    -- What was wrong: the Bike Shop's bicycles came out at 0 and 8 --
    -- each bike sliced in half at ankle height with its top row missing,
    -- and the leftmost rack fused into the wall and towered to 32.  The
    -- shop's whole L-shaped counter stood at wall height, a 16px slab
    -- you could not see over.  Both Cable Club rooms lost their stools
    -- (a walkable cell, so they flattened to floor) and their machine
    -- came out 0/8/16 in the same object.  And the Game Boy link poster
    -- above the door has $32 in its bottom-left corner, so the poster
    -- had a pond in it -- the shore-set trap, and TRADE_CENTER's link
    -- table carries the other one, $48.
    CLUB = {
      -- The wall band stays ONE 16px face.  6 is the striped panel,
      -- 52 the fluted pillar that breaks it every three cells (its
      -- rounded foot, 53, stands one row lower on the floor and is
      -- walkable, so it stays flat ground in front of the band).
      -- Drawn INTO the band and therefore wall as well: the two
      -- bicycles against the Bike Shop's wall (1/2/3 over 17/18/19,
      -- exactly two tile rows = exactly the band's height), the Cable
      -- Club's link poster (48/49/50/51 -- 50 is $32, the shore trap
      -- that had it recessing to -2), and the Trade Center's pair of
      -- lit notice boards (63/68/68/69 over 66/67/67/70).
      -- The bicycles keep their `wall` pin as the degradation path, but
      -- `mounted` below lifts them off the panel -- see there.
      wall = { 1, 2, 3, 6, 17, 18, 19, 48, 49, 50, 51, 52, 63, 66, 67,
               68, 69, 70 },
      -- Counters, half a cell high -- the house rule for anything you
      -- lean on.  The Bike Shop's L: the till run's top (7/8, the
      -- tileset's own counterTiles) with its inside corner (54), east
      -- arm (16) and end cap (5), all over the front panel 23/24.  8px
      -- is one clean band, so the drawn front stands up and the counter
      -- top stays a top; at 12 or 16 it reads as a wall stub.
      -- 71/72/73/74 is the TRADE_CENTER link table, which shares that
      -- same 23/24 front: its surface is drawn from ABOVE (two Game
      -- Boys lying on it, cables between), so it belongs riding the top
      -- face, not standing up.  72 is $48, the second shore trap.
      counter = { 5, 7, 8, 16, 23, 24, 54, 71, 72, 73, 74 },
      -- The Colosseum's battle machine: a console drawn face-on, four
      -- tiles wide and three rows tall, grilled side towers (59/62 and
      -- 55/58), a dark screen bay (60/61, 56/57) and the two white
      -- horns that crown it (64/65).  24px is its drawn height, so
      -- `desk` folds the whole drawing upright as one machine instead
      -- of the 0/8/16 rubble the detector left.
      desk = { 55, 56, 57, 58, 59, 60, 61, 62, 64, 65 },
      -- The two stools that flank each Cable Club machine: seat 42/43
      -- over base 38/39, in every one of the four placements across
      -- both rooms and nowhere else in the tileset.  Their cells are
      -- walkable, so without a pin they were floor; at seat height a
      -- character standing on one sits on it.
      stool = { 38, 39, 42, 43 },
      -- The showroom bicycles -- six of them standing on the Bike Shop
      -- floor, in two columns, each drawn 3 tiles by 2 side-on.  A THIN
      -- standee pool, not `bookcase`: a bike is nearly all air (two
      -- wheel rings and a frame), and collapsing a rack of them onto a
      -- one-cell-deep box at full height would trade six bicycles for
      -- one blank 32px panel wearing a bicycle print.  As cutouts they
      -- segment cleanly -- the drawing has floor margin on three sides
      -- and its own black outline seals the wheels -- and the standee
      -- builder's connected-component split gives each bike its own
      -- feet in its own cell even where a lower bike's handlebar stem
      -- touches the wheel of the one drawn above it.
      -- 11/12/14 the saddle and bar row, 27/28/9 the frame and wheels.
      --
      -- Their own pool at TWO voxels rather than `prop`'s five, which is
      -- the whole reason `bike` exists.  The segmentation was never the
      -- problem -- the mask the detector cuts is a clean bicycle, wheels,
      -- forks, handlebars and all.  Depth was: every stroke of a line
      -- drawing extruded five voxels closes the gap to its neighbour with
      -- its own side faces, so off-axis (which is every camera rung but
      -- flat) the air inside the frame filled in and the showroom's six
      -- bicycles came out as one dark lump against the wall.  At two the
      -- negative space survives and they read as bicycles again.
      bike = { 9, 11, 12, 14, 27, 28 },
      -- The toolbox and the standing pump beside the shop's south wall
      -- (29/13 over 21/22), twice.  A separate pool from the bicycles
      -- on purpose, and the thicker one: a toolbox is a deliberate
      -- object with a body, where a bike is a silhouette.
      --
      -- Kept as the DEGRADATION PATH only.  The `bike_shop_toolbox`
      -- building template (see `buildings.CLUB`) claims these cells and
      -- models the drawing properly -- a per-pixel standee is the wrong
      -- primitive for a box, and 10 voxels of it turned every black
      -- outline pixel into a 10-deep bar.  Buildings runs before the
      -- standee scan, so where the template stamps, this pin never
      -- fires; without a profile it is still better than the volume
      -- path.
      billboard = { 13, 21, 22, 29 },
      -- The Bike Shop floor's second checker phase.  It is NOT in the
      -- tileset's walkable list, so the cells it floors resolve by rule
      -- 4 and it rose as a wall stub -- or, worse, got swept into the
      -- bicycle beside it and dragged to 8px.  It is floor; it is flat.
      ground = { 30 },
      -- THE TWO BICYCLES AGAINST THE SHOWROOM'S NORTH WALL.  Same object
      -- as the six on the floor -- 24x16 of bicycle seen side-on, wheels
      -- on the floor line -- but drawn INTO the wall band instead of onto
      -- the floor, which is a different problem entirely:
      --
      --   a class pin resolves a whole 8x8 tile, so `wall` (what these
      --   carried) paints the bicycle flat on the panel: a green wall
      --   with a bicycle printed on it, which is what the shop looked
      --   like;
      --   and nothing automatic can cut it out either.  The panel behind
      --   it is tile 6's stripe -- a #aaa field ruled with #555 every
      --   four rows -- and #555 is a flood BOUNDARY, so a silhouette
      --   flood comes back with three full-width wall stripes welded
      --   across the bike (rows 3, 7 and 15 of the drawing).  Naming the
      --   background shades instead (prop_bg) cannot work either: the
      --   bicycle's own basket is drawn in the very #aaa and white the
      --   wall field uses.
      --
      -- So the silhouette is authored -- but MEASURED, not drawn by hand.
      -- 6 is the plain panel these three tile columns are painted over,
      -- and it is perfectly regular, so compositing 6 across the same 3x2
      -- grid and flooding the background in through the pixels that still
      -- MATCH it separates bicycle from wall exactly: 247 pixels, one
      -- connected component, no stripe left on it and no hole in it.
      -- That is also why `under` is six 6s -- the wall wears the panel
      -- the artist drew everywhere else along the same run.
      --
      -- `depth` 2 for the same reason the `bike` pool above is 2, and
      -- because a family shares a silhouette: these are the showroom's
      -- bicycles, leaning on the wall rather than standing in the room.
      -- The slab juts 2 voxels SOUTH of the band, so they stand in front
      -- of the wall and overhang the walkable cell a little -- which is
      -- what a bicycle leaning on a wall does.  Collision is untouched.
      --
      -- Only BIKE_SHOP places this grid on the club atlas, at tile (1,0)
      -- and (6,0).  The same six tile ids DO pair up in gate.png (both
      -- Route gate upper floors and all four Safari rest houses), but
      -- that is a different image and `mounted` is keyed per tileset, so
      -- the pattern cannot reach them.
      mounted = {
        {
          w = 3,
          depth = 2,
          tiles = {  1,  2,  3,
                    17, 18, 19 },
          under = {  6,  6,  6,
                     6,  6,  6 },
          pixels = {
            ".........XXX............",
            "..XXXXX.XXXX............",
            "..XXXXXXXXXX............",
            "..XXXXXXXXXX............",
            "..XXXXXXXXXXXXX.........",
            "..XXXXXXXXXXXXXX........",
            "..XXXXXXXXXXXXXX........",
            "..XXXXXXXXXXXXXX..XXX...",
            ".XXXXXXXXXXXXXXXXXXXXXX.",
            "XXXXXXXXX..XXXXXXXXXXXXX",
            "XXXXXXXXX.XXXXXXXXXXXXXX",
            "XXXXXXXXX.XXXXXXXXXXXXXX",
            "XXXXXXXXX.XXXXXXXXXXXXXX",
            "XXXXXXXXX..XXX..XXXXXXXX",
            ".XXXXXXX....X...XXXXXXX.",
            "...XXX.....XXX....XXX...",
          },
        },
      },
      -- Left to the derived default on purpose:
      --   $0F $1F    the main floor checker -> walkable, ground
      --   $0A $1A    the dark slab under the Bike Shop's exit warp -> a
      --              threshold mat, walkable, flat
      --   $35        the pillar's rounded foot -> its cell is walkable
      --              (you walk in front of the pillar), so it lies flat
      --              against the 16px band, which is what a plinth does
      --   $26-$29 $2C-$2F  the octagon painted on both Cable Club
      --              floors.  Ground markings seen from above, and every
      --              cell they sit in is walkable, so rule 3 already
      --              keeps them perfectly flat.  ($26/$27 are shared
      --              with the stool bases above and pinned there; they
      --              appear nowhere else in either room.)
    },

    -- The S.S. Anne, inside: both cabin decks and their corridors, the
    -- bow, the kitchen, the captain's room -- and two Kanto houses
    -- (Cerulean's badge man, Fuchsia's Good Rod fisher) that borrow the
    -- liner's furniture set.  Twelve maps, and SS_ANNE_CAPTAINS_ROOM plus
    -- SS_ANNE_KITCHEN between them place every tile the group uses.
    --
    -- Everything was wrong here, in every one of the ways indoors goes
    -- wrong.  The wall-touching cabin table and the BED were merged into
    -- the wall and towered to 32px, so a bunk read as a bank of lockers
    -- wearing a porthole on top.  The corridor wall band measured 24px
    -- instead of 16.  In the two houses the band came out at height 0 --
    -- the drawing runs off the top of the map, so the detector had no run
    -- to measure and the room had no walls at all.  Every stool, chair and
    -- staircase sat in a WALKABLE cell and flattened to floor, so the
    -- captain's room had no stairs, no chairs and no seat.  And the
    -- barrels' top-left tile is $48, which the engine's stale-cache shore
    -- set counts as water in every tileset but SHIP_PORT: each barrel had
    -- a pond dug into its lid.
    SHIP = {
      -- The wall band stays ONE 16px face.  Blank courses (16), the
      -- lower trim (18/19), the portholes (2/3), and the band's corner
      -- pieces where a corridor meets it (32/33 white, 48/49 trim,
      -- 34/50 the black outer corner).  $32 (50) is the shore-set trap:
      -- unpinned it recesses into a pond lip in the middle of a
      -- bulkhead, and it drags the whole 16x16 cell down with it,
      -- because rule 2 judges a cell by its bottom-left tile.
      --
      -- The black rim is wall too, not void: 17 is the band's cap seen
      -- from above (so the fold tops the bulkhead with it), 21/22 the
      -- vertical faces that run down both sides of every corridor, 51
      -- the ship's south bulkhead, and 5/6/37/38 the four corners of the
      -- notch each cabin doorway is cut into.  Left to the detector
      -- these came out 8, 16, 24 and 48 in the same room.  Only $01 --
      -- pure black, the space OUTSIDE the hull -- is left alone: the
      -- void rule flattens it, which is what darkness should do.
      --
      -- 14/15/30/31 are the cabin door drawn INTO the band (its cell is
      -- walkable, since the player steps on it to warp, so unpinned the
      -- door punched a flat hole through the wall).  84/85 are the
      -- captain's chair BACK, drawn into the band above his seat -- so
      -- the chair reads as a high-backed swivel chair jutting from the
      -- wall instead of a separate tower.  45/61 are the bow deck's
      -- rope rail and 46/47/62/63 its stepped bulwark: the same 16px
      -- course, so the open deck is fenced at one height.
      wall = { 2, 3, 5, 6, 14, 15, 16, 17, 18, 19, 21, 22, 30, 31, 32,
               33, 34, 37, 38, 45, 46, 47, 48, 49, 50, 51, 61, 62, 63,
               84, 85 },
      -- Every table in the group, at 12px: the kitchen's three banquet
      -- tables (twelve tile rows deep), the counter run along the
      -- kitchen's south wall, the captain's desk, and the writing table
      -- in the two houses.  Corners 9/12, north edge 10, side edges
      -- 25/28, the surface 44, the plain apron 11 and the drawer front
      -- 59/60.  One 8px band folds up, so the drawn apron stands as the
      -- front and every row above rides the top face in drawn order --
      -- which is how the tableware stays tableware: the plate (26), the
      -- covered platter (64/65/80/81), the kitchen stove's burner grid
      -- (53) and the captain's open book (68/69) are all drawn FROM
      -- ABOVE, so they belong lying on the top face, not standing up as
      -- cutouts.  59/60 doubles as the chest of drawers at the foot of
      -- every cabin bunk; 12px puts it a hand above the mattress, which
      -- is where a bedside chest belongs.
      table = { 9, 10, 11, 12, 25, 26, 28, 44, 53, 59, 60, 64, 65, 68,
                69, 80, 81 },
      -- The cabin bunk: a mattress drawn from above, so its art stays on
      -- the TOP face and it lies low.  70/71 the pillow, 86/87 the
      -- mattress.  (Its drawer end is in `table` above.)
      bed = { 70, 71, 86, 87 },
      -- Seats, in the standee pool: the round stool that appears in
      -- every cabin, the badge house and the captain's room (7/8 seat
      -- over 23/24 legs), and the captain's own chair (66/67 seat over
      -- the same 23/24 base, its back pinned into the wall above).
      -- Seat height 8 keeps a character standing on the stool's
      -- (walkable) cell sitting at seat height rather than floating.
      -- The drawings have real floor margin on all four sides, so the
      -- black-outline flood eats the checker around them and leaves the
      -- seat whole.
      stool = { 7, 8, 23, 24, 66, 67 },
      -- The captain's storage rack: three shelf ranks (54 left, 43
      -- right) drawn four tile rows tall against the wall.  TALL, not
      -- deep -- the bookcase builder collapses it onto one cell of depth
      -- at its drawn height, and adopts the row above (9/12, pinned
      -- `table` as the tabletop corners they also are) as its cap.
      -- Boxed by the detector it was a 16px stub with the wall beside it
      -- towered to 24.
      bookcase = { 43, 54 },
      -- The galley barrels -- three down the kitchen's east wall, one in
      -- the captain's room, one in each house.  72/73 the mouth, 88/89
      -- the banded body.  72 is $48, the shore-set trap that had each
      -- barrel resolving to water at -2.
      --
      -- This is Lt. Surge's trash can REDRAWN PIXEL FOR PIXEL on the ship
      -- atlas: lay the two masks side by side and the only difference is
      -- that the gym's floor stripes cross the gym copy's background,
      -- which the flood keeps and this one has no need of.  So it takes
      -- the same treatment and the same numbers as GYM's can -- see there
      -- for why the mouth and base ellipses are measured and the height,
      -- well and taper are authored.
      --
      -- Scanned: six placements on the SHIP atlas and no others --
      -- SS_ANNE_KITCHEN (13,5), (13,7) and (13,9) down the east wall,
      -- SS_ANNE_CAPTAINS_ROOM (4,1), and one each in CERULEAN_BADGE_HOUSE
      -- and FUCHSIA_GOOD_ROD_HOUSE at (7,7), both of which are ship
      -- interiors reusing the tileset.  Twenty-one more hits are id
      -- collisions on other atlases and no business of this entry; the one
      -- worth naming is VERMILION_DOCK, because SHIP_PORT is a near-twin
      -- of this image -- but its $48/$49/$58/$59 are a hull panel, not a
      -- barrel (diffed pixel for pixel), so the pin is NOT copied there.
      can = { 72, 73, 88, 89 },
      can_cap = 9,
      can_base = 4,
      can_height = 9,
      can_well = 5,
      can_taper = 4,
      heights = { can = 9 },
      -- The stairs, both flights, in every map that has them (1F, 2F,
      -- 3F, B1F and the captain's room).  Same two drawings the whole
      -- game uses, and the warp table says which is which: 41/42/57/58
      -- is the light flight that always leads UP a deck, climbing east
      -- the way its treads step; 39/40/55/56 is the dark stairwell that
      -- always leads DOWN, sinking westward.  Both cells are walkable,
      -- so unpinned both were flat floor and the decks did not connect.
      stair_e = { 41, 42, 57, 58 },
      stair_down_w = { 39, 40, 55, 56 },
      -- Left to the derived default on purpose:
      --   $01        pure black outside the hull -> void, flat darkness
      --   $04 $23    deck planking and grating   -> walkable, ground
      --   $0D $1D    cabin floor checker         -> walkable, ground
      --   $4A        cabin door threshold        -> walkable, ground
      --   $24 $34    the dark slab under the exit warp in the cabins and
      --              the two houses: a threshold mat with no wall around
      --              it, walkable, and flat is the honest reading
      --   $14        the SEA around SS_ANNE_BOW.  It is the one tile id
      --              the stale-cache water set names in every tileset,
      --              and here that guess is simply RIGHT -- the bow deck
      --              really does stand in open water, so it is the one
      --              trap tile in this group that must NOT be pinned.
    },

    -- Vermilion Dock: the quay, the boarding gangway, and the S.S. Anne
    -- herself moored alongside.  One map, and it is the only place in
    -- the game where a whole VESSEL is drawn as map art rather than as a
    -- building sprite.
    --
    -- The detector read the liner as a volume and raised her 48px --
    -- three cells, taller than she is long is wide -- with her columns
    -- stepping 48/40/24/0 across the hull, so the drawing was folded
    -- UPRIGHT and smeared up a lumpy monolith.  Both ends of the hull
    -- fell to 0 instead, and the port bow ($40/$41/$51) sat in a cell
    -- whose bottom-left tile is open water, so rule 2 sank it to -2 and
    -- the ship had a hole in her nose.
    --
    -- (This tileset is the one place the engine does NOT count $32 and
    -- $48 as shore -- Map.lua's NO_SHORE_TILESETS -- because $32 IS the
    -- gangway here.  So the usual shore trap does not apply, and $14 is
    -- honest open water.  Nothing in this entry is dodging a water
    -- fallback; the whole entry is about the ship.)
    SHIP_PORT = {
      -- The hull, every tile of her, as a `roof`: a box wearing its art
      -- on the TOP face.  That is what the drawing IS -- the liner seen
      -- from above and slightly astern, funnels and boats and deck rail
      -- on the top rows, hull plating on the bottom two -- so folding it
      -- upright was always going to smear.  28px of freeboard reads as a
      -- liner beside a quay at 0 and water at -2 without towering, and
      -- the side bands crop from each edge tile's own art, so the flank
      -- the player faces wears the hull plating that is drawn there.
      -- Rows north to south: bow rail and boat deck (0/2-7/9/11-15),
      -- superstructure (16-31), midships (32-47), waterline strake
      -- (48-53 and 61-63 in the stern), hull plating (64-69, 77-79) and
      -- the boot topping (81-85, 90-93).
      roof = { 0, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 14, 15,
               16, 17, 18, 19, 21, 22, 23, 24, 25, 28, 29, 30, 31,
               32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 44, 45, 46, 47,
               48, 51, 52, 53, 54, 55, 56, 57, 61, 62,
               64, 65, 66, 67, 68, 69, 77, 78, 79,
               81, 82, 83, 85, 90, 91, 93 },
      -- The quayside crates, a 2x2-tile box each (86/87 lid, 1/80
      -- body), stacked two cells deep in all four corners of the dock,
      -- and the pallet stacks flanking the gangway head (49).  A crate
      -- IS a 16px cube: one course, art folded up the face it shows.
      -- Unpinned the corner stacks fused into one taller volume.
      wall = { 1, 49, 80, 86, 87 },
      -- The delivery van parked on the north quay: drawn face-on, four
      -- tiles by two, with clear pavement all round it -- so it takes
      -- the standing per-pixel cutout with a body (10 voxels), not a
      -- rectangular block that would swallow the air above its cab.
      -- 72/73/74/75 the cab and box, 88/89/60/76 the wheels and skirt.
      billboard = { 60, 72, 73, 74, 75, 76, 88, 89 },
      -- Left to the derived default on purpose:
      --   $0A        the quay's paving -> walkable, ground
      --   $32 $3B    the gangway planks -> walkable, ground, so the walk
      --              from the quay to the warp stays flush at 0 and
      --              meets the hull's flank rather than climbing it
      --   $14        open water -> the tileset's own water, -2
      --   $3A        the shaded strip along the quay's foot.  Its cell's
      --              bottom-left tile is water, so rule 2 puts it at
      --              water level -- which is correct: it is the dock's
      --              shadow lying ON the water, and the 2px lip between
      --              it and the paving is exactly the shoreline the
      --              water class exists to draw.
    },

    -- The facilities: twenty-one maps off one 96-tile atlas -- Silph Co's
    -- ten office floors, the four Rocket Hideout basements, the four
    -- Pokemon Mansion floors, the Power Plant, and the Cinnabar and
    -- Saffron gyms.  One pin therefore has to read right in a laboratory,
    -- an open-plan office, a burnt mansion and a gym at once; where a
    -- graphic genuinely means two things the note says which reading won.
    -- The failures are the usual indoor ones, louder: the detector raised
    -- whole wall COLUMNS to 48px, stood the lab consoles up as 32px
    -- cabinets towering over the very band they are drawn INTO, fused
    -- vertical runs of computer terminals into 48px monoliths, boxed the
    -- potted-plant rows into one slab wearing leaves on its top face, and
    -- left both staircases lying flat on the floor.  Silph Co's lobby
    -- island is tile $14 -- the engine's stale-cache water id -- and sank
    -- into a pond in the middle of the foyer.
    FACILITY = {
      -- The wall band stays ONE 16px face: the dark courses (42/58
      -- horizontal, 43/44 vertical, 45/46 the top corners, 59/60 the
      -- bottom caps) and Silph Co's own pale striped band (87/89).  A
      -- north-south run of 43/44 is one continuous drawing, so unpinned
      -- the detector measured the whole column and raised it to 48.
      --
      -- Everything DRAWN BUILT INTO that band is `wall` too, the
      -- Center's-healing-console rule, so it reads as equipment jutting
      -- from the band rather than a separate tower:
      --   74/75 the machine's two dials over 76/77 its footed base -- one
      --     graphic serving the Cinnabar Gym's quiz consoles, Silph Co's
      --     and the Power Plant's equipment banks and the Mansion's lab
      --     rigs.  Drawn three rows tall under a one-row wall cap, which
      --     is why the detector called it 32
      --   9/10 screen over 25/26 base: the computer terminal.  It is
      --     ALSO the free-standing maze wall of Rocket Hideout B2F/B3F
      --     and the terminal rows of the Power Plant hall, and 16 -- its
      --     drawn height -- is right in every one of them
      --   64/80 the Mansion 2F balustrade seen face-on, 65/81 its
      --     north-south run.  65 repeats down a whole column, so it
      --     towered exactly like the wall did
      --   86/88 the lift doors of Silph Co: a walkable warp cell, but a
      --     pin is look-only, so the doors stand in the wall band
      --     instead of lying flat as a mat (the Center does the same
      --     with its window/warp tile)
      --   8/24 and 36/37 the shutters the card-key doors and the
      --     Cinnabar Gym quiz gates stamp CLOSED at runtime
      --     (field.cardKeyDoors' blocks $54/$5F/$2D).  They are in no
      --     map's block list, so nothing but this line covers them; the
      --     detector read them as an 8px stub lying in the doorway
      wall = { 8, 9, 10, 24, 25, 26, 36, 37, 42, 43, 44, 45, 46,
               58, 59, 60, 64, 65, 74, 75, 76, 77, 80, 81, 86,
               87, 88, 89 },

      -- The tall display cabinet of the Mansion and Silph 3F/8F/9F: cap
      -- row 40/41 over two ranks of 56/57, one cell wide and drawn FOUR
      -- rows tall.  A tall drawing, not a deep one, so it takes the
      -- Mart's shelf-rack treatment and collapses onto a one-cell-deep
      -- box at its full 32px -- as `wall` it flattened into a bench two
      -- cells deep, which is the shape of its footprint, not the shape
      -- of the thing.  Its base course is the computer terminal's own
      -- 25/26, listed under `wall` above and therefore shared: that
      -- stays a 16px block, and reads as the cabinet's plinth.
      bookcase = { 40, 41, 56, 57 },

      -- The grey slab family -- every desk, bench, worktop and service
      -- counter in the tileset is cut from these seven pieces: 13/14 the
      -- top corners, 2 the top edge between them, 29/30 the body's side
      -- edges, 53 its fill, 68/69 the legs, 18 the counter's front panel
      -- (the tileset's own counterTiles).
      --
      -- `counter` -- 8px, half a cell -- not `table` or `desk`, because
      -- the drawing is a TOP surface seen from above with one row of
      -- front elevation at its south end: one clean band folds exactly
      -- that bottom row (68/69 legs, or 18) up as the front and rides
      -- every row above it on the top face in drawn order, which is what
      -- a seven-cell Silph Co bench actually looks like.  At 12 or 16
      -- the same drawing reads as a wall stub, the failure the Center's
      -- counters are pinned against.
      --
      -- 13/14 and 29/30 double as the CAP and body of the wall consoles
      -- (blocks $60/$62/$64/$66/$7F).  The benches win the tie on count
      -- -- 142 block placements across 18 maps against the consoles' 105
      -- across 14 -- and the compromise costs the consoles nothing: the
      -- capped rows sit NORTH of the 16px dial face, so an 8px ledge
      -- behind a 16px machine is occluded from every southward camera.
      counter = { 2, 13, 14, 18, 29, 30, 53, 68, 69 },

      -- Plants, the thin standee pool, as in every other interior.  Two
      -- drawings: the tall potted palm of Silph Co, the Hideout and the
      -- Mansion (crown 5/6/21/22 over pot 7/15/23/31, a 1x2-cell
      -- object), and the gym planter of Cinnabar, Saffron and the
      -- Mansion (crown 39/47, bowl 55/63, box 61/62).  Unpinned the
      -- detector fused a six-plant row into one box wearing the leaf
      -- dither as a lid.  The crown's checker highlights share the
      -- floor's shades so the mask drains some of them -- the same
      -- accepted trade as the Center's bush.
      prop = { 5, 6, 7, 15, 21, 22, 23, 31, 39, 47, 55, 61, 62, 63 },

      -- Both flights UP, both climbing EAST.  3/4/19/78 is the one-cell
      -- open staircase of the Mansion (1F->2F, 2F->3F) and the Hideout
      -- (B1F->Game Corner): white treads whose risers step up toward the
      -- upper right.  90/91 over 67/52 is Silph Co's own stairwell, set
      -- into the north wall band on every floor -- courses of tread whose
      -- east ends step back one notch at a time.  BOTH cells are
      -- WALKABLE (19 and 67 are the tileset's warp tiles), so unpinned
      -- they resolved to flat ground and the steps were painted on the
      -- floor.  Silph's drawing is the one genuinely ambiguous flight in
      -- the tileset -- read as a west rise it builds a ramp that leaves a
      -- gap against the east jamb, so east it is, which also makes one
      -- consistent story out of every up-stair in the group.
      stair_e = { 3, 4, 19, 78, 52, 67, 90, 91 },
      -- The staircase DOWN (11/12/27/28): three treads in a black
      -- stairwell, shortening and darkening west to east, so the flight
      -- descends EAST into the dark.  One graphic again, for every
      -- down-stair in the group.  (Where the Mansion 3F variant hangs
      -- directly under the wall band, block $73, the engine's door fold
      -- claims the cell first -- 27 is one of the tileset's doorTiles --
      -- and stands the art up in the band as a doorway.  That reads
      -- fine, and the fold runs after this profile, so it is not
      -- something a pin can or should undo.)
      stair_down_e = { 11, 12, 27, 28 },

      -- The rubble drifts of the Mansion and the Power Plant (83/84 over
      -- 54/38): two black-outlined boulders per cell on a plain grey
      -- ground, tiling wall-to-wall across whole rooms.  Drawn ROUND, so
      -- they take the overworld canopy's archetype -- one voxel hull per
      -- 16x16 cell carved from the darkest-pixel outline -- which is the
      -- only class that keeps a repeating field as separate lumps: a
      -- standee pool would cluster a whole drift into one giant flat
      -- cutout, and the volume path gave 16px slabs with 48px towers
      -- wherever a drift touched a wall.
      cylinder = { 38, 54, 83, 84 },

      -- Silph Co 1F's lobby island (tile $14), the cross-shaped dither
      -- the reception terminals ring.  $14 is one of the three ids the
      -- engine's stale-cache water set claims in EVERY tileset, and it
      -- is not on this tileset's walkable list, so it fell straight to
      -- `water` and opened a pond in the middle of the foyer.  It is a
      -- floor-level mat drawn from above: flat.
      ground = { 20 },

      -- Left to the derived defaults on purpose, having been checked:
      --   51, the Hideout's black fill, is all-black art, so the void
      --     rule already flattens it -- which is what a room's interior
      --     darkness should be
      --   32/33/48/49 -- the four quarter-tiles the Hideout's spinner
      --     arrows and the Saffron/Silph warp diamonds are assembled
      --     from -- and 94, the Hideout's floor panel, are on the
      --     tileset's walkable list and come out flat ground unaided
      --   1 (the checker floor), 17 (the Mansion's upper-floor boards)
      --     and 66/82 (the entrance carpet) likewise
      --   the other two stale-cache water ids, $32 and $48, are never
      --     placed by any of the twenty-one maps, so only $14 above
      --     needed the guard
    },

    -- Pokemon Tower's seven floors and Agatha's room (one tileset).
    -- Every floor is the same octagonal chamber: a ring of wall panels
    -- ($09/$0A over $19/$1A) cut out of a mid-grey mass ($11), with a
    -- field of gravestones inside it, and Agatha's room is that chamber
    -- shrunk.  The ring and the mass the detector already reads as one
    -- 16px course (probed) -- they are listed anyway so the answer is
    -- authored rather than inferred from a repeat count, and so the
    -- panels can never fuse into the gravestones that touch them.
    -- What the detector got WRONG was everything else: the headstones
    -- came out as 8px stubs with their arched tops dropped, both
    -- stairwells were flattened by the walkable-cell rule, and the
    -- potted palms lost their crowns to a 16px box.
    -- (Nothing here needs pinning against the void rule: the tileset's
    -- one all-black tile is $47, and no map in the group places it.)
    CEMETERY = {
      -- One 16px course: the chamber's wall ring ($09/$0A over
      -- $19/$1A), the grey mass beyond it ($11) so the room reads as a
      -- chamber cut into solid stock rather than a fence standing on a
      -- plain, and Agatha's north band ($20 over $30).
      wall = { 9, 10, 25, 26,
               17,
               32, 48 },
      -- The reception counter of POKEMON_TOWER_1F -- the only counter in
      -- the group, and the ROM's own counterTiles for this tileset name
      -- $12 as exactly that.  It is an L that fences the receptionist
      -- into the south-east corner: the east-west arm drawn face-on
      -- ($02 the surface over $12 the front panel, eight cells of it)
      -- meeting the north-south arm drawn from above ($1D/$1E, eight
      -- tile rows, which the volume path would have towered to 64px).
      -- The first pass put all four in `wall` and the barrier came out
      -- a full-height partition with the receptionist hidden behind it
      -- to the shoulders.  Half a cell is what a counter is: she leans
      -- on it, the drawn surface ($02) rides the top face and the drawn
      -- panel ($12) folds up the front, and both arms come out the same
      -- height so the corner turns cleanly instead of stepping.  The
      -- cells stay blocked either way -- pins are look-only.
      counter = { 2, 18, 29, 30 },
      -- The gravestones ($05/$06 over $15/$16): a headstone drawn
      -- face-on, one per cell, 314 of them across the seven floors and
      -- Agatha's room.  The volume path measured the drawing as its
      -- bottom row alone and left an 8px stub -- the plinth without the
      -- stone.  `post` is the per-CELL standee pool: each cell is
      -- extracted on its own as a per-pixel cutout 6 voxels deep, so
      -- the arched top comes back and a 4x2 block of graves stands as
      -- eight separate stones instead of one 32px sheet with the back
      -- row floating above the front (which is what one shared
      -- billboard cluster would have made of them).  The stone's white
      -- side margins let the background flood in; its own white checker
      -- band is sealed by the black arch and survives.
      post = { 5, 6, 21, 22 },
      -- The flight UP to the next floor ($03/$04 over $13/$14): real
      -- rising steps, climbing east the way the risers are drawn (short
      -- at the west, tall at the east -- the same drawing idiom as Red's
      -- house).  Its collision tile is $13, which IS in the tileset's
      -- walkable list, so rule 3 had laid the whole flight flat; and its
      -- south-east tile is $14, the water-fallback trap id -- harmless
      -- only because the cell's own bottom-left is $13, and pinned here
      -- so it can never matter.
      stair_e = { 3, 4, 19, 20 },
      -- The flight DOWN ($0B/$0C over $1B/$1C): a sunken stairwell.
      -- The drawn step edges are high and lit at the WEST and fall away
      -- dark to the east, so the flight descends eastward -- the mirror
      -- of Red's bedroom stair.  Walkable ($1B) and flattened for the
      -- same reason as the flight up.
      stair_down_e = { 11, 12, 27, 28 },
      -- The potted palm that flanks Mr. Fuji's shrine on 7F and stands
      -- in Agatha's room ($27/$2F crown, $37/$3F fronds, $3D/$3E
      -- planter): a plant, so the THIN standee pool, like every other
      -- interior plant.  It is drawn 24px tall across THREE tile rows,
      -- which is why the box path dropped its crown row entirely and
      -- kept a 16px planter; a standee takes the whole drawing at its
      -- real height.  It backs onto the wall ring, and a separate pool
      -- keeps it from being absorbed into it.
      prop = { 39, 47, 55, 63, 61, 62 },
      -- (Nothing else needs an entry.  The tower's floor ($01) and 5F's
      -- healing pad ($22) are walkable, so rule 3 lays them flat where
      -- they are drawn; the mass, ring, graves, stairs and palm above
      -- are every other tile the eight maps place.)
    },

    -- The two Underground Paths (Route 5<->6 north-south, Route 7<->8
    -- west-east): one blockset, two maps, and the plainest geometry in
    -- the game -- a tiled corridor cut out of black.  Most of it was
    -- already right, because the black it is cut from ($10) is solid
    -- black and the void rule flattens it (`10v00` over every border
    -- block), and the lattice floor ($0B/$0C) with the diagonal shadow
    -- strip along its west wall ($15/$18) are walkable and lie flat.
    -- Two things were not.
    --
    -- The SOUTH rim.  The corridor's near wall is drawn as a single 8px
    -- light line ($02) with black under it, so the volume builder
    -- measured a one-row drawing and raised half a course -- an 8px
    -- kerb (`02w08` along the whole bottom row of
    -- UNDERGROUND_PATH_WEST_EAST) facing a proper 16px far wall
    -- (`06w16`/`09w16`).  Pinned, the corridor closes with one band all
    -- round.  The east and west rim lines ($16/$17) already read 16 --
    -- their columns repeat -- and join the same authored course so the
    -- whole enclosure is one decision.
    --
    -- The STAIRS.  $03/$04 over $13/$14 is a real flight drawn in
    -- profile, treads climbing to the upper right, and it is the warp
    -- back up to the surface at both ends of both corridors.  Its cell
    -- is walkable, so it resolved to flat ground and the staircase was
    -- a painting (`03g00 04g00 / 13g00 14g00`).  stair_e builds the
    -- flight the drawing shows, rising east.  $14 is also the $14
    -- WATER-FALLBACK id: the walkable cell was hiding the trap here
    -- rather than dodging it, and the pin settles it either way.
    UNDERGROUND = {
      wall = { 6, 9,               -- $06 over $09, the far wall band
               2,                  -- $02, the near wall's light line
               22, 23 },           -- $16/$17, the east and west rims
      stair_e = { 3, 4, 19, 20 },  -- $03/$04 over $13/$14
      -- The blockset also carries the wall's unplaced corner variants
      -- ($05/$08 north-west, $07/$0A north-east, $11 south-west, $12
      -- south-east).  Neither map places them; they belong with the
      -- wall band above if one ever does.
    },

    -- The approach to the Pokemon League: two maps, INDIGO_PLATEAU (the
    -- forecourt the League itself stands on) and ROUTE_23 (the long
    -- climb up to it, with its badge-check gates).  Everything this
    -- blockset draws is one piece of architecture -- striated rock
    -- walls, white pillars, and the bird STATUES that line both the
    -- avenue and the plaza.  29 of its 73 blocks are never placed, so
    -- every tile named below really is one of these two maps'.
    --
    -- A statue is built exactly like the badge gyms' (see GYM above):
    -- one cell of FIGURE ($10/$12 over $28/$29) standing on one cell of
    -- PLINTH ($15/$16 the cap over $30/$31 the plaque).  47 of them --
    -- 12 on INDIGO_PLATEAU, six a side down the avenue, and 35 more
    -- across ROUTE_23's plaza (blocks $42/$43; the $25/$26 twins that
    -- stand the same statue on grass are never placed).
    --
    -- What the detector made of them is the bug this entry exists for.
    -- On the avenue the statues stack with NO gap: the plinth's plaque
    -- row is drawn directly above the next figure's head, so the
    -- flood-fill joined all six of a column into ONE region 24 tile rows
    -- tall, and the volume builder's repeat scan read 32px down one half
    -- of the drawing and 24px down the other.  Each row came out as a
    -- continuous stepped RIDGE of boxes wearing the statue art folded
    -- onto its south face -- probed INDIGO_PLATEAU tiles (16,12)-(17,35)
    -- at 32/24 and (22,12)-(23,35) mirrored.  ROUTE_23's plaza statues
    -- stand alone and fared no better: 24px boxes with the figure's top
    -- row skipped outright.
    --
    -- Pinned the gyms' way the ridge becomes statues.  The plinth is a
    -- SOLID 16px `wall` block; the figure is a per-pixel cutout 5 voxels
    -- deep (the thin `prop` pool) that rides the plinth's top face
    -- through the authored-box support rule and collapses to the
    -- plinth's SINGLE cell of footprint -- Structures' wall-support case,
    -- so the base never marches backwards.
    --
    -- The one thing the gyms did not have to deal with: $28/$29 is
    -- SHARED.  The same bird is drawn again at the foot of every white
    -- pillar, framed there by the pillar's black edge ($25/$26 over that
    -- same $28/$29, blocks $18/$1B) -- 80 of them, 76 down ROUTE_23 and
    -- four on INDIGO_PLATEAU (its two outer corners and the pair
    -- flanking the League's recess).  So $25/$26 joins the same pool:
    -- pinning half a cell would have stood a half-height bird under a
    -- wall.  That in turn is why the pillar itself is pinned -- see the
    -- last paragraph of `wall`.
    PLATEAU = {
      -- ONE 16px course for every piece of masonry here.
      --
      -- $03 is the striated rock face, 2436 placements and the bulk of
      -- both maps.  It already read 16 nearly everywhere, but in the
      -- columns of INDIGO_PLATEAU's rim that stand over a corner pillar
      -- the repeat scan came out 24 -- a stagger in the plateau's
      -- skyline (probed `03w24` at tiles (8,0)-(9,2), (12,0)-(13,2) and
      -- their two mirrors).  Authored, the rim is one course.
      --
      -- $0D/$0F/$0E are the League's outer wall -- top band, face and
      -- base.  The same three tiles draw the Pokemon League's own
      -- facade, the long walls flanking the avenue, and every
      -- badge-check gate down ROUTE_23.
      --
      -- $15/$16 + $05/$06 + $30/$31 are the pilaster: cap, shaft, and
      -- the plaque base.  $15/$16 over $30/$31 IS the statue's plinth --
      -- the artist drew the same stone twice -- which is why one pin
      -- serves the gate corners and the statues alike.
      --
      -- $2E/$2F the white pillar shaft and $20/$21 its cap change no
      -- HEIGHT: they derive 16 already.  What the pin buys is
      -- `authored`, which is exactly what the prop support rule tests.
      -- Without it a pillar-foot bird finds no support, drops to ground
      -- level, and leaves a hole punched clean through the pillar
      -- (probed, shot, then fixed).
      -- TWO courses (32px) for the masonry that ENCLOSES both maps -- the
      -- plateau's rim and every wall around the terraces.  It is drawn two
      -- cells tall, which is exactly the height of a statue on its plinth
      -- (a 16px plinth under a 16px standee), and that is the read: you are
      -- walking in a walled compound whose wall matches the statues lining
      -- it, not a room with a 16px skirting.  At one course the rim was a
      -- kerb you appeared to look over.
      --
      -- $03 the striated rock face, $0D/$0F/$0E the League's outer wall
      -- (top band, face, base -- the same three tiles draw the League's
      -- facade, the walls flanking the avenue and every badge-check gate
      -- down ROUTE_23), and $2E/$2F the white pillar shaft with $20/$21 its
      -- cap.  These four groups are the enclosure.
      cliff = { 3, 13,
                32, 33, 46, 47 },
      -- THE GATE WALLS, stacked rather than laid out in depth.  $0D/$0F/$0E
      -- (13/15/14 -- top band, face, base) draw the League's facade, the
      -- walls flanking the avenue and every badge-check gate down ROUTE_23,
      -- as FOUR tile rows: 13 / 15 / 15 / 14.  That is 32px of artwork
      -- depicting one wall, and at one class per row it built four boxes
      -- marching north, so the wall was 32px DEEP -- you saw the southmost
      -- row's face and the rest hid behind it.
      --
      -- `bookcase` collapses the run onto a single one-cell-deep box at its
      -- full drawn height: bands from the south are base, face, face, top
      -- band, and the two rows behind are vacated.  Same mechanism the
      -- Mart's back wall uses.
      -- ...and the PILASTER stacks with it.  $05/$06 is its shaft, and it
      -- is drawn only ever inside a pilaster, so it needs no rule.  Without
      -- this the pale columns stood 16px against a 32px brown wall and
      -- their top vertices sat a whole course below the wall's crown.
      bookcase = { 14, 15, 5, 6 },
      -- Tile 13 is DUAL-USE and needs resolving per position.  It is the
      -- gate wall's TOP BAND (block $28's first row) and it is also the
      -- BASE COURSE under a column of rock face (blocks $18/$1A/$1B, last
      -- row).  Pinned `bookcase` outright the second use became a one-row
      -- rank -- an 8px stub under the rock, 352 of them over both maps.
      --
      -- ABOVE cannot tell them apart, which is what `when_below` is for.
      -- Scanned over both maps through the engine's own tileAt, the tile
      -- above a 13 is the rock face $03 for 140 base courses AND for 64
      -- gate bands -- so a rule on `above` misfires on those 64 (it did:
      -- their runs came out 2 and 3 bands instead of 4).  BELOW splits it
      -- exactly: the wall's own face $0F sits under the top band and under
      -- nothing else, 336 against 352.  So 13 defaults to `cliff` and is
      -- promoted where the face is drawn beneath it.
      --
      -- 14 and 15 need no rule: 14 only ever sits under 15, 15 only ever
      -- under 13 or 15.
      when_below = {
        [13] = { { below = { 15 }, class = "bookcase" } },
        -- The pilaster's CAP ($15/$16) is the same stone as the statue's
        -- plinth top -- the artist drew it twice -- so it too resolves per
        -- position.  Scanned over both maps: a cap with the shaft $05/$06
        -- beneath it is a pilaster (76 of them) and one with the plaque
        -- base $30/$31 beneath it is a statue's plinth (47).  Default
        -- `wall`, promoted here, so the plinth keeps its single course and
        -- the statue standing on it still totals the 32px the wall is.
        [21] = { { below = { 5 }, class = "bookcase" } },
        [22] = { { below = { 6 }, class = "bookcase" } },
      },
      -- The other two ends of the same pair of drawings, keyed the other
      -- way round.  A pilaster is capped at BOTH ends, so its lower cap has
      -- the shaft ABOVE it (8 placements); and the plaque base $30/$31 is a
      -- pilaster's foot when the shaft is above it (68) but a statue's
      -- plinth bottom when the cap $15/$16 is (47).
      when_above = {
        [21] = { { above = { 5 }, class = "bookcase" } },
        [22] = { { above = { 6 }, class = "bookcase" } },
        [48] = { { above = { 5 }, class = "bookcase" } },
        [49] = { { above = { 6 }, class = "bookcase" } },
      },
      -- The vacated rows behind a collapsed wall take the cell ABOVE the
      -- run rather than the default hidden floor: here that is more rock
      -- face on ROUTE_23 and the plateau's paving or grass on INDIGO_
      -- PLATEAU, so the wall reads as set INTO the terrace instead of
      -- standing in front of a trench of synthesized ground.
      bookcase_backfill = "above",
      -- and no shelf relief: what the collapse carries here is MASONRY,
      -- whose courses are the wall itself rather than panes set behind
      -- a frame.  Sinking them cut a stepped bevel into the League's
      -- walls and the pilasters (shot before it was turned off).
      bookcase_relief = false,
      -- ONE course, and it must stay one: $15/$16 + $05/$06 + $30/$31 is
      -- the pilaster -- cap, shaft, plaque base -- and $15/$16 over $30/$31
      -- IS the statue's plinth, the artist having drawn the same stone
      -- twice.  Raising it would carry every statue standee up to 48px and
      -- break the very match the cliff height was chosen for.
      -- $05/$06 is NOT here: it moved to `bookcase` above, and a tile
      -- listed in two groups resolves by whichever `pairs` order wins --
      -- half the pilasters kept the shaft as `wall`, which broke the run
      -- and left their caps as isolated 8px stubs.  One group per tile.
      wall = { 21, 22, 48, 49 },
      -- The statues, and the same bird at the pillar feet.  Black-outline
      -- segmented: the outline and everything it encloses stay, the sky
      -- and the paving around them flood away.
      prop = { 16, 18, 40, 41, 37, 38 },
      -- Round drawings, one voxel ball per 16x16 cell -- the treatment
      -- the overworld's canopies and Celadon's hedge take.
      --
      -- $07/$08 over $17/$18: the seven canopies planted on pillar tops
      -- along ROUTE_23 (blocks $44/$45; the $0F block that tiles four of
      -- them together is never placed).  Boxed, the canopy art smeared
      -- down the whole pillar column beneath it.
      --
      -- $2A/$2B over $22/$1D: the boulders strewn across ROUTE_23's
      -- middle terrace (blocks $02/$13/$16), one per cell and NOT
      -- walkable.  As boxes they sat flat enough to look painted onto
      -- the path; as balls they read as the obstacles they are.
      cylinder = { 7, 8, 23, 24,
                   29, 34, 42, 43 },
      -- The Route 23 sign, one cell, block $48's only placement.
      -- Unpinned it probed `09w00 0Aw00 / 19w08 1Aw08` -- an 8px stub
      -- with its board skipped.  Same thin plate on a stick every other
      -- outdoor sign gets.
      signpost = { 9, 10, 25, 26 },
      -- The Route 22 gate's roof, drawn from ABOVE and filling
      -- ROUTE_23's last two block rows ($3D the tiling, $3E/$44 its
      -- edges, $40/$41 the corners).  Art on the TOP face -- the way
      -- SHIP_PORT's hull is pinned -- rather than folded up a 16px kerb.
      -- It stands past the map's last walkable row (you warp to
      -- ROUTE_22_GATE before you reach it), so this is a tidy-up rather
      -- than a fix.
      roof = { 61, 62, 64, 65, 68 },
      -- The ground painted where a pinned figure's cell used to be:
      -- $23, the pale paving both maps are floored with.  It is also the
      -- white the pillars are drawn in, so the cell a pillar-foot bird
      -- vacates reads as more pillar -- where the neighbour vote left a
      -- BLACK hole, having nothing to elect (all four neighbours of that
      -- cell are wall).  On the avenue and the plaza the statues' own
      -- cells simply keep the paving they stand on.
      prop_ground = { [16] = 35, [18] = 35, [40] = 35, [41] = 35,
                      [37] = 35, [38] = 35 },
      -- Deliberately NOT pinned:
      --
      -- $14, the water -- 1446 placements, the pond on ROUTE_23's middle
      -- terrace -- and its bank shading $32/$33/$1F.  $14 and $32 are
      -- two of the three stale-cache water ids the trap is named for,
      -- but here they are honestly water: TILEANIM_WATER animates $14,
      -- the pond is real, and $32/$33/$1F are drawn in the TOP half of
      -- water cells as the waterline itself, so the cell rule dropping
      -- them to -2 is what the art means.  Left to fall through to the
      -- engine's water set.  ($48, the third trap id, is not in this
      -- atlas at all -- it stops at $45.)
      --
      -- $0B/$0C over $1B/$1C, the barred doors: the Pokemon League's two
      -- and Victory Road's two.  They are the tileset's own doorTiles,
      -- so the door fold already stands them upright in the facade;
      -- probed 16px identically before and after this entry.
      --
      -- $23/$2C/$2D are in the walkable list outright, and $45 is the
      -- tileset's grassTile, which derives its own standing-tuft pin.
      --
      -- The Victory Road entrance is a `buildings` template
      -- (victory_road_gate, at the bottom of this file): 36x6 tiles at
      -- ROUTE_23 (0,58), and its ends are built out of $25/$26/$28/$29
      -- and $15/$16/$05/$06.  Buildings claim their tiles before any of
      -- the above can reach them -- probed `b` class over all 216 of
      -- them, unchanged by this entry.
    },
  },

  -- Buildings whose whole sprite is voxelized band by band (lib/Buildings.lua,
  -- the pipeline in assets/docs/buidling_to_voxel/).  A building is matched by its
  -- exact tile grid -- the drawings are catalogued in assets/docs/buildings/ -- so
  -- every map that places the same art gets the same model: one entry
  -- voxelizes Red's house, Blue's house, Bill's, the Copycat's and the two
  -- Fuchsia houses alike.
  --
  -- Only the BAND TABLE is authored here, because only it needs a human to
  -- read the drawing.  Everything measurable is measured off the pixels:
  -- the silhouette, the taper rate (which IS the roof's slope), the eave
  -- height, and every window and doorway (a non-black region its own black
  -- frame seals off).  Fields:
  --
  --   tiles      the tile-id grid that identifies the building, rows of the
  --              8px tile atlas, north row first
  --   roofRows   how many rows off the top are drawn as TOP-FACING roof;
  --              the rest of the drawing is the facade, seen face-on
  --   roofBack   rows laid along the north rim, one row per voxel of depth
  --   roofFront  rows laid along the south rim (the fascia and eave course)
  --   roofCycle  the row run the middle depth cycles; its length must be
  --              the roof texture's period or the courses will not line up
  --   slab       roof thickness in voxels
  --   frontEave  how far the roof overhangs the facade
  --   ledge      a band that juts two voxels past the walls (an awning),
  --              or nil
  --   seal       sides the drawing runs off rather than closing with its
  --              own outline, as a string of n/s/e/w; the silhouette
  --              flood does not seed there. Only needed by a drawing
  --              trimmed flush to its art -- one whose base course is a
  --              row of brick rather than the black threshold every other
  --              building stands on. Omit it unless the fill says
  --              otherwise: sealing a side the drawing does NOT run off
  --              swallows the terrain beside it.
  --
  -- Nothing here describes the roof's SHAPE, because nothing needs to: the
  -- topmost drawn row of each column is the elevation profile, so a drawn
  -- taper becomes a slope and a roof drawn from straight above comes out
  -- level.  That is why the flat-roofed civic block and its sixteen
  -- relatives -- every Center and Mart, the gyms and gates, the department
  -- store and Silph Co -- share one band table below, differing only in
  -- their tile grids.  The sloped ones fall into three groups just as
  -- cleanly, by the depth of the roof band: 16 rows (Red's house), 32
  -- (Oak's lab) or 64 (the museum).  Before authoring a new one, check
  -- whether its roof band is already pixel for pixel one of those.
  --
  -- assets/docs/buildings/B26 is deliberately absent.  Its drawing has no
  -- black base course -- it ends on a row of light brick -- so the
  -- silhouette flood, which comes in from the border through light pixels,
  -- climbs up through the wall and hollows it out.  Every other building
  -- is sealed by a black threshold row.  Reading it would mean changing
  -- the flood itself, which every model here depends on, for one scenery
  -- placement.
  buildings = {
    -- Gen 2's Johto set. Every town building in Johto is drawn from three
    -- courses -- a ridge cap, a striped roof band, an eave -- over a brick
    -- facade, and the whole catalogue is two footprints: the 4x4-cell
    -- civic block (Center, Mart, gym, the larger houses) and the 4x2-cell
    -- cottage. Both are here because the volume detector cannot read
    -- either one.
    --
    -- What defeats it is Johto's facades REPEATING their wall course. The
    -- detector reads a column's drawn unit off its tile sequence, and its
    -- trim-foot rule -- "when the two rows above the front are identical
    -- the column is a repeat wearing a trim" -- was written for cliff
    -- plateaus. The civic block's column is 10/0D/0D/0A/1A/1A/1A/01: the
    -- two rows above its base course ARE identical, so every Center and
    -- Mart in Johto read as a 16px repeat, which also means flat-topped
    -- (a repeat never roofs). That is the flat-lidded box with the roof
    -- printed on it -- eight tile rows of drawing standing two rows high.
    --
    -- Roof bands, read off the art: row 0 the black ridge line, row 1 its
    -- white highlight, then the vertical stripe field (period 1 down the
    -- roof -- the stripes run WITH the slope, so any row of the band
    -- serves), closing on a four-row fascia of black/shade/black/shade.
    -- So `roofBack` 2 lays the cap along the north rim, `roofFront` 4 the
    -- fascia along the south, and the middle cycles the stripe field.
    TilesetJohto = {
      -- OLIVINE LIGHTHOUSE.  Four cells wide and fourteen tall -- twenty-
      -- three tile rows of nothing but brick between the gallery and the
      -- door, which is exactly what defeats the volume path: its trim-foot
      -- rule reads the repeating $1A/$07/$1C course as a 16px pattern and
      -- lays the whole tower flat on the ground.  Stated as a template the
      -- shaft is facade, so all twenty-three rows become elevation and the
      -- lighthouse stands up as the tallest thing in Johto.
      --
      -- The cap is the lantern gallery, not a roof: rows 0-2 are the glass
      -- seen from above (the hatched field) and row 3 the deck's dark
      -- fascia -- hence `roofFront` 8 rather than the 4 every gabled Johto
      -- roof uses, and a cycle that stops at 23 where the hatching does.
      -- It must come FIRST: the shaft's plain courses are a tile-for-tile
      -- match for `johto_block_brick`, which would otherwise claim slices
      -- of the tower and leave nothing for this grid to sit on.
      {
        id = "johto_lighthouse",
        tiles = {
          { 0x31, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x34 },
          { 0x41, 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x44 },
          { 0x41, 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x37, 0x38, 0x07, 0x07, 0x07, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 8, roofCycle = { 2, 23 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- THE PAGODAS.  Sprout Tower (VIOLET_CITY blocks 11-12, rows 0-2) and
      -- the Burned Tower (ECRUTEAK_CITY blocks 2-3, rows 0-2) are the SAME
      -- drawing, tile for tile: a tiled cap over two eaved tiers over a
      -- doorway, ten tile rows of it.  Six of those rows are the two tiers,
      -- and the tiers are identical to each other -- which is precisely
      -- what the volume path's trim-foot rule calls a repeat, so both
      -- towers lay flat on the grass like the lighthouse did.  Stated here
      -- the six rows below the cap are all facade, so the tower stands
      -- five cells tall.  The `$3B`/`$3D` at the ends of the last two rows
      -- are the hedge the doorway is cut into; they are in the grid
      -- because they are in the drawing's rectangle, and both towers are
      -- planted in the same hedge.
      {
        id = "johto_pagoda",
        tiles = {
          { 0x31, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x34 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x3B, 0x1A, 0x27, 0x28, 0x1B, 0x1B, 0x1C, 0x3D },
          { 0x3B, 0x01, 0x29, 0x2A, 0x02, 0x02, 0x16, 0x3D },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- THE BELL TOWER, the same pagoda drawing run to SEVEN tiers instead
      -- of two -- ECRUTEAK_CITY cell (36,0), the tower the city is built
      -- around.  It is so tall that its cap is off the top of the map, so
      -- the ten-row `johto_pagoda` grid above never matched: the four roof
      -- rows it wants are at cell rows -2 and -1, where the border block
      -- is.  Fourteen rows of identical tier is the volume path's repeat
      -- again, so the whole tower lay flat.
      --
      -- Same fix as `johto_block_plain_clipped` at the bottom of this
      -- list: `topRows` supplies the cap from the atlas, the matcher
      -- places on the fourteen tier rows plus the doorway that ARE on the
      -- grid, and the model is built from the complete drawing.  It cannot
      -- collide with `johto_pagoda` in either direction -- that grid leads
      -- with a roof this one does not have on the map, and this grid is
      -- longer than that whole template.
      {
        id = "johto_pagoda_tall",
        topRows = {
          { 0x31, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x34 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
        },
        tiles = {
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x22, 0x41, 0x1B, 0x1B, 0x1B, 0x1B, 0x44, 0x25 },
          { 0x50, 0x51, 0x52, 0x52, 0x52, 0x52, 0x54, 0x55 },
          { 0x3B, 0x1A, 0x27, 0x28, 0x1B, 0x1B, 0x1C, 0x3D },
          { 0x3B, 0x01, 0x29, 0x2A, 0x02, 0x02, 0x16, 0x3D },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- ECRUTEAK'S SIX-CELL HALL, the wide one with the brown top --
      -- ECRUTEAK_CITY cell (16,9), the building beside the theatre.  It
      -- is the roofed-wall drawing below stretched to six cells with a
      -- doorway cut in the middle, and it is FIRST of the $53 family for
      -- the usual reason: placement is first-claim-wins and the four-cell
      -- templates that follow would otherwise take bites out of its
      -- facade and stand second buildings through it.
      {
        id = "johto_ecruteak_hall",
        tiles = {
          { 0x31, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x34 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x27, 0x28, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x29, 0x2A, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- ECRUTEAK'S ROOFED WALL.  The compounds around the Burned Tower and
      -- the Tin Tower are enclosed by a tiled wall, drawn 8x6 tiles (4x3
      -- cells) and repeated all round the city -- ECRUTEAK_CITY blocks
      -- (6,7)-(7,8) is one of them.  It wears the lighthouse's gallery caps
      -- ($31/$41/$51 west, $34/$44/$54 east) over a $53 tile field and a
      -- $52 fascia, and NOT the $10/$11/$0D/$0E ridge every other Johto
      -- roof uses -- which is exactly why no template reached it and the
      -- volume path laid all of them flat on the grass as brown decking.
      -- Four tile rows of roof over two of wall, so the same band table as
      -- the mart with the wall course shortened.
      {
        id = "johto_ecruteak_wall",
        tiles = {
          { 0x31, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x34 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- THE PAIR WEST OF THE MART AND THE CENTRE -- ECRUTEAK_CITY cells
      -- (22,19) and (12,25).  Same drawing as the wall above with a
      -- doorway ($27/$28 over $29/$2A) cut into its facade, which is the
      -- one difference, and the one that stopped the wall's grid matching:
      -- two buildings in the middle of town went on lying flat as brown
      -- decking while the compound walls around them stood up.
      {
        id = "johto_ecruteak_house",
        tiles = {
          { 0x31, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x34 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x1A, 0x1B, 0x27, 0x28, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x29, 0x2A, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- THE DANCE THEATRE -- ECRUTEAK_CITY cell (36,24).  Four cells
      -- square, and it wears the LIGHTHOUSE's hatched gallery cap
      -- ($36/$48 field between the $31/$41/$51 and $34/$44/$54 verges)
      -- rather than the $53 tiled field the rest of the city does, so no
      -- $53 template could reach it and the lighthouse's own grid is
      -- twenty-eight rows of $07 shaft it does not have.  Doorless on
      -- this face, a window bay at each end.
      {
        id = "johto_ecruteak_gallery_block",
        tiles = {
          { 0x31, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x34 },
          { 0x41, 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x44 },
          { 0x41, 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x1A, 0x26, 0x26, 0x1B, 0x1B, 0x26, 0x26, 0x1C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- VIOLET'S LONG HALL: the Ecruteak hall's drawing again, but with
      -- six courses of tile on the roof instead of four, so the roof is
      -- half again as deep and the walls sit that much lower.
      {
        id = "johto_violet_hall",
        tiles = {
          { 0x31, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x34 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x41, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x27, 0x28, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x29, 0x2A, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 48, roofBack = 2, roofFront = 4, roofCycle = { 2, 43 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- THE ROUTE GATEHOUSES.  Every gate between two Johto routes is one
      -- of these two drawings -- the same shell, the same pair of windows
      -- ($26/$26 either side of the middle), and only the roof differs --
      -- and neither had a template, so every gate on the map was a flat
      -- box with its roof painted on the lid.
      {
        id = "johto_gate",
        tiles = {
          { 0x31, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x34 },
          { 0x41, 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x44 },
          { 0x41, 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x44 },
          { 0x51, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52, 0x54 },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the same gatehouse under the brick roof, at Olivine
      {
        id = "johto_gate_brick",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the 4x4-cell civic block with MART over its door
      {
        id = "johto_mart",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x37, 0x38, 0x18, 0x19, 0x07, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x17, 0x17, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- its twin with the POKe sign
      {
        id = "johto_pokecenter",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x37, 0x38, 0x08, 0x09, 0x07, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x17, 0x17, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the 4x2-cell cottage: the same courses with the stripe band cut
      -- to one tile row, the ordinary house of every Johto town
      {
        id = "johto_house",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x1B, 0x37, 0x38, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the gym: the civic block stretched to six cells, GYM on the
      -- lintel ($23/$24) over the door, a window bay at each end
      {
        id = "johto_gym",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x23, 0x24, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x1A, 0x26, 0x26, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x26, 0x26, 0x1C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x37, 0x38, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the same six-cell hall with a plain lintel: Elm's lab and the
      -- civic halls that share its drawing
      {
        id = "johto_hall",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x1A, 0x26, 0x26, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x26, 0x26, 0x1C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x37, 0x38, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the four-cell civic block with a brick front and one window bay
      {
        id = "johto_block_brick",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x26, 0x26, 0x1C },
          { 0x1A, 0x1B, 0x37, 0x38, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- and its plaster-fronted twin (Olivine's warehouses)
      {
        id = "johto_block_plain",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x37, 0x38, 0x07, 0x07, 0x07, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- doorless cottages, the scenery of every town: four, three and two
      -- cells wide on the same two-course roof
      {
        id = "johto_house_4x2",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      {
        id = "johto_house_3x2",
        tiles = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      {
        id = "johto_house_2x2",
        tiles = {
          { 0x10, 0x11, 0x11, 0x12 },
          { 0x0A, 0x0B, 0x0B, 0x0C },
          { 0x1A, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x02, 0x16 },
        },
        roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- ROUTE 29'S NORTH GATE, and the one shape in Johto that no
      -- template above could ever reach.  It is `johto_block_plain` down
      -- to the tile, but it stands hard against the map's north edge:
      -- its four roof rows would be at cell rows -2 and -1, and what is
      -- actually up there is the border block, a wall of trees.  The
      -- drawing is CLIPPED BY THE MAP, not continued on the neighbour --
      -- unlike the Pokemon Tower, whose missing half really is drawn on
      -- ROUTE_10 -- so there is nothing to claim and nothing to read
      -- back.  With only the lower four rows on the grid the eight-row
      -- template never matched, the facade fell to the volume path, and
      -- the whole gate folded into a wedge with its door painted flat
      -- across the top.
      --
      -- `topRows` supplies the missing roof from the atlas rather than
      -- from the map, which is exactly what it is for: the matcher still
      -- places by `tiles` alone, so the four rows it can see, while the
      -- MODEL is built from the complete eight-row drawing.  The offsets
      -- line up with no fudge because `topRows` here is precisely
      -- `roofRows` deep (32px, four rows), so the model's first depth
      -- slice is `tiles[1]` and the stamp lands where it matched.
      --
      -- LAST IN THE LIST ON PURPOSE.  These four rows are the bottom
      -- half of every `johto_block_plain` in Johto, so on any ordinary
      -- placement this would match too.  Placement is first-claim-wins
      -- (see Buildings.build), and the full template is above, so by the
      -- time this one is tried those cells are already claimed and only
      -- the roofless gate is left.
      {
        id = "johto_block_plain_clipped",
        topRows = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
        },
        tiles = {
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
          { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x26, 0x26, 0x1C },
          { 0x1A, 0x07, 0x37, 0x38, 0x07, 0x07, 0x07, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- MAHOGANY'S NORTH GATE, the building the Lake of Rage road runs
      -- past -- MAHOGANY_TOWN cell (8,0).  The brick-fronted twin of the
      -- gate above and clipped by the map's north edge the same way, so
      -- the same treatment: `topRows` for the roof it has no room to
      -- draw, and LAST in the list because these four rows are the bottom
      -- half of every `johto_block_brick` in Johto.
      {
        id = "johto_block_brick_clipped",
        topRows = {
          { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
          { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
        },
        tiles = {
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x26, 0x26, 0x1C },
          { 0x1A, 0x1B, 0x37, 0x38, 0x1B, 0x1B, 0x1B, 0x1C },
          { 0x01, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x16 },
        },
        roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
        slab = 4, frontEave = 4, ledge = nil,
      },
    },

    OVERWORLD = {
      -- assets/docs/buildings/B30: the POKEMON TOWER -- the one drawing
      -- in the catalogue that STRADDLES A MAP BOUNDARY.  Twelve of its
      -- twenty rows stand in ROUTE_10's last rows (the 64px purple roof
      -- band plus two window courses); the other eight -- five more
      -- courses and the base with the door -- are on LAVENDER_TOWN,
      -- where the tower begins at tile row 0.  Modelled per map it came
      -- out as two buildings, one per half.
      --
      -- `topRows` composites ROUTE_10's twelve rows ABOVE the matched
      -- grid, so the model is built from the COMPLETE twenty-row drawing
      -- -- 96px of facade under the real 64px roof -- while placement
      -- still matches only the eight Lavender rows.  Its `claimOnly`
      -- twin below claims the ROUTE_10 rows and stamps nothing, so the
      -- roof half does not also stand as its own building.
      --
      -- BOTH COME FIRST IN THIS LIST ON PURPOSE.  The tower's upper
      -- twelve rows are `gabled_block_6x6` tile for tile -- the artist
      -- drew the top of the tower as an ordinary six-cell block -- so
      -- that template matches at ROUTE_10 (24,132) too.  Placement is
      -- first-claim-wins (see Buildings.build), so claiming here before
      -- the generic block reaches it is what keeps the second tower from
      -- being stamped behind this one.
      --
      -- The 13-id last row is kept from the first attempt: the bare
      -- 12-wide body grid is B14's lower two-thirds tile for tile, and
      -- the extra id stops this template stamping inside
      -- `flat_block_6x6`'s three placements (`matches` walks a row to
      -- its own length, while `read` composites only #tiles[1] columns,
      -- so a 13th id constrains placement without entering the drawing).
      {
        id = "pokemon_tower",
        topRows = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
        },
        tiles = {
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79, 17 },
        },
        roofRows = 64, roofBack = 8, roofFront = 8, roofCycle = { 8, 31 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the tower's roof half, where it actually stands on ROUTE_10:
      -- claimed flat so the drawing does not ALSO fold up as a building
      -- behind the modelled tower (see topRows above)
      {
        id = "pokemon_tower_top",
        claimOnly = true,
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
        },
      },
      -- assets/docs/buildings/B07: the two-storey gabled house.  Coursed cap over
      -- a gable wall, an awning with its double black underline, then the
      -- ground floor with the door.  7 placements, Red's and Blue's among
      -- them.  Course rhythm: a dark line every 4 rows.
      {
        id = "gabled_house",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 34, 10, 10, 40, 41 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 34, 11, 12, 10, 10, 34, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = { 24, 31 },
      },

      -- assets/docs/buildings/B31: Oak's lab.  The same architecture with a roof
      -- band twice as deep -- the extra rows are DEPTH, not height, so the
      -- lab is a bigger footprint under the same storey.  Its cross-hatch
      -- roof texture repeats every 8 rows, and it has no awning: the band
      -- that would be one is the roof's own eave course.
      {
        id = "oaks_lab",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 10, 75, 75, 10, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 11, 12, 10, 10, 10, 10, 10, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B03: the flat-roofed commercial block --
      -- Celadon's diner, hotel, chief's house and prize room, the Bike
      -- Shop, the Fan Club, Mr. Psychic's, the Underground Path entrances.
      -- 15 placements, the most of any voxelized drawing.  The lattice
      -- field is drawn from straight above, so the measured taper is flat
      -- and the whole band is depth under one level roof; the eave course
      -- is the roof's own south rim, lab-style, no awning.  Lattice period
      -- 8, the lab's rhythm again.
      {
        id = "flat_commercial",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 75, 75, 75, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B05: every Pokemon Center in the game
      -- (Celadon, Cerulean, Cinnabar, Fuchsia, Lavender, Pewter,
      -- Saffron, Vermilion, Viridian, Mt Moon, Rock Tunnel). B03's
      -- block with the POKe sign hung beside the door; the sign is
      -- too wide to be a pane, so it stays flush.
      {
        id = "pokecenter",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 66, 67, 75, 31 },
          { 78, 26, 27, 28, 74, 74, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B06: every Poke Mart (Cerulean,
      -- Cinnabar, Fuchsia, Lavender, Pewter, Saffron, Vermilion,
      -- Viridian). The Center's twin, MART on the sign.
      {
        id = "pokemart",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 68, 69, 75, 31 },
          { 78, 26, 27, 28, 74, 74, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B02: the plain 4x4 block: one window
      -- course over blank brick and no door. 15 placements, scenery
      -- in every city bar the Celadon Mart roof stair.
      {
        id = "flat_block_4x4",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B08: the same block two cells deeper,
      -- 6 placements, all scenery.
      {
        id = "flat_block_4x6",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B13: the 6x4 scenery block, 4
      -- placements.
      {
        id = "flat_block_6x4",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B14: the 6x6 scenery block, 3
      -- placements.
      {
        id = "flat_block_6x6",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B27: the 8x4 scenery block, one
      -- placement on Route 11.
      {
        id = "flat_block_8x4",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B09: the wide storefront: Celadon's
      -- Game Corner, the Pokemon Mansion, Cinnabar Lab, the Safari
      -- Zone gate and Fuchsia's meeting room.
      {
        id = "game_corner",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B15: Celadon Mansion and the Route 6
      -- and Route 12 gates.
      {
        id = "celadon_mansion",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B18: the Route 2 gate, and the museum's
      -- east entrance beside it in Pewter.  The museum HALL itself is
      -- B24 below, a different drawing with a sloped roof.
      {
        id = "route_2_gate",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B29: Fuchsia Gym, the block with GYM
      -- on the sign.
      {
        id = "fuchsia_gym",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 34, 47, 63, 34, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 34, 34, 34, 34, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 10, 10, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B28: the Route 5 underground-path
      -- gate.
      {
        id = "route_5_gate",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B21: the Route 22 league gate, the
      -- widest of the family at 12 cells.
      {
        id = "route_22_gate",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B25: the Power Plant.
      {
        id = "power_plant",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B22: Celadon's department store: six
      -- window courses over the MART sign.
      {
        id = "celadon_mart",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 11, 12, 10, 10, 68, 69, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 27, 28, 26, 26, 74, 74, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B20: Silph Co. Twelve cells of plot
      -- and ten courses of windows under the same roof band, so it
      -- stands as the tallest thing in Kanto.
      {
        id = "silph_co",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B24: the Pewter museum's hall, and the only
      -- building in the family with a SLOPED roof: the same 2:1 taper the
      -- lab and Red's house are drawn with, over a roof band twice the
      -- lab's depth.  The drawing repeats its whole lattice-and-course
      -- motif -- rows 8..31 again at 32..55 -- which is what fixes the
      -- cycle at 24 rather than the bare lattice's 8: the drawing proves
      -- the period.  The last band (rows 56..63) is the roof's fascia,
      -- wider than the wall it covers, so it stays in the roof band and
      -- lands on the south rim.
      {
        id = "museum",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 64, roofBack = 8, roofFront = 8, roofCycle = { 8, 31 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B10: the gym. Cinnabar, Pewter,
      -- Vermilion and Viridian wear this drawing, and so does the
      -- Fighting Dojo next door to Saffron's. Oak's lab's roof band
      -- exactly, tile for tile, over a facade with GYM on the sign.
      {
        id = "gym",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 34, 47, 63, 34, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B16: the big-city gym: Celadon,
      -- Cerulean and Saffron. Two cells wider than the standard
      -- gym, and it carries the GYM sign twice.
      {
        id = "gym_large",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 34, 47, 63, 34, 34, 47, 63, 34, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B01: the commonest drawing in the
      -- game at 19 placements, and every one of them scenery: a
      -- gabled block with two window courses and no door. Red's
      -- house's roof band, tile for tile, but no awning under it.
      {
        id = "gabled_block_4x3",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B04: the little 4x2 cottage, 12
      -- placements and nearly all of them somebody's home: Mr
      -- Fuji's, the Cubone house, Bill's grandpa's, the Name
      -- Rater's, the Viridian school house, the Route 8 underground
      -- path.
      {
        id = "gabled_cottage",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 11, 12, 10, 10, 40, 41 },
          { 78, 26, 27, 28, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B17: the wide 6x2 house: Cerulean's
      -- badge, trade and trashed houses.
      {
        id = "gabled_house_wide",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 11, 12, 35, 10, 10, 35, 10, 10, 40, 41 },
          { 78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B11: the 6x2 scenery block, 5
      -- placements, no door.
      {
        id = "gabled_block_6x2",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 34, 35, 10, 10, 35, 10, 10, 40, 41 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B34: the 4x2 scenery block, one
      -- placement in Fuchsia.
      {
        id = "gabled_block_4x2",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 34, 10, 10, 40, 41 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B33: the Route 5 day care.
      {
        id = "daycare",
        tiles = {
          {  5,  6, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 34, 34, 34, 31 },
          { 15, 10, 10, 10, 11, 12, 10, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B26: the Route 10 scenery block,
      -- structurally the museum's twin -- Oak's lab's roof band,
      -- and its rows 8..31 repeat at 32..55 exactly as the museum's
      -- do. It needs `seal` because its drawing has no black base
      -- course: it ends on a row of light brick, and unsealed the
      -- flood climbs in from the south border through the mortar
      -- and hollows the wall out (72% of the sprite survives
      -- instead of 95%, in 65 pieces instead of 1).
      {
        id = "gabled_block_6x6",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
        },
        roofRows = 64, roofBack = 8, roofFront = 8, roofCycle = { 8, 31 },
        slab = 4, frontEave = 4, ledge = nil, seal = "s",
      },
    },

    FOREST = {
      -- assets/docs/buildings/B12: the Safari Zone rest houses --
      -- Center, East, North, West and the Secret House. A
      -- corrugated roof over a plank facade; its stripe repeats
      -- every 5 rows, not the OVERWORLD lattice's 8.
      {
        id = "safari_rest_house",
        tiles = {
          {  8,  9,  9,  9,  9,  9,  9, 12 },
          { 24, 25, 25, 25, 25, 25, 25, 28 },
          { 40, 41, 42, 43,  1,  1, 41, 44 },
          { 56, 41, 58, 59, 41, 41, 41, 60 },
        },
        roofRows = 17, roofBack = 5, roofFront = 3, roofCycle = { 5, 9 },
        slab = 4, frontEave = 4, ledge = nil,
      },
    },

    DOJO = {
      -- F01: the starter-ball table in Oak's lab (one placement in the
      -- game: OAKS_LAB cell 6,3) -- the first FURNITURE through the
      -- band pipeline, and the first drawing whose plot is smaller than
      -- its grid. Its 24 rows read: 0-15 the tabletop seen from above
      -- (black rim, white highlight course, grey field); 16-18 the top
      -- slab's own front edge, black/#555/black -- which is exactly
      -- what the rim treatment paints, so slab = 3 and those rows fold
      -- into the roof band instead of extruding under it; 19-21 the
      -- base band, corner feet and the inset dark panel between them.
      --
      -- The legs stand on open FLOOR: the measured ground line lands
      -- two rows short of the grid (see Buildings measure), and `depth`
      -- keeps the plot to the blocked cell row -- the grid's third row
      -- is the walkable cell the player faces the table from, matched
      -- so the flat leg art is claimed off the floor, not so the model
      -- stands on it. 16 top rows onto a 16px plot map 1:1: roofBack
      -- covers the whole depth, nothing cycles, and roofCycle is
      -- unreachable behind it. The Poke Ball sprites ride the `table`
      -- pin's height (VoxelScene.groundAt reads the collision tile, not
      -- this model), so the tileset entry above overrides that height
      -- to the 6px this drawing actually stands.
      {
        id = "lab_table",
        tiles = {
          { 41, 59, 59, 59, 59, 42 },
          { 78, 57, 57, 57, 57, 79 },
          { 88, 89, 89, 89, 89, 90 },
        },
        roofRows = 19, roofBack = 16, roofFront = 0, roofCycle = { 2, 13 },
        slab = 3, frontEave = 0, ledge = nil, depth = 2,
      },
      -- F02: the computer desk on the lab's west side (OAKS_LAB cell
      -- 0,1) -- the one DESK-SET template: the pipeline's region
      -- classification at PART granularity (see Buildings
      -- deskSetModel). The desk is the sibling lab table (fascia rows
      -- 16-18, base 19-21); on it stand a monitor over its keyboard
      -- (left), a computer tower over a keyboard and mouse (middle),
      -- and a sheet of paper LYING FLAT (right). Upright parts anchor
      -- their drawn bottom row to the desk's top plane and wear their
      -- own drawn tops as lids; flat parts lie one voxel proud at
      -- drawn row = depth row -- the same 1:1 the tabletop itself is
      -- drawn with. The roof fields are inert (roofRows = 0 keeps the
      -- recess scan over the whole drawing, which is what sinks the
      -- monitor's screen and the tower's slots). Same drawing, same
      -- grid, stands in the Hall of Fame on the GYM atlas --
      -- registered there below.
      {
        id = "lab_computers",
        tiles = {
          { 91, 92, 93, 94 },
          { 54, 55, 85, 95 },
          { 88, 89, 89, 90 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 2,
        desk = { fascia = { 16, 18 }, base = { 19, 21 } },
        parts = {
          { kind = "upright", x = { 2, 13 }, top = { 0, 2 },
            facade = { 3, 10 }, depth = 4 },              -- the monitor
          { kind = "flat", x = { 1, 13 }, rows = { 11, 14 } },  -- keyboard
          { kind = "upright", x = { 14, 21 }, top = { 0, 3 },
            facade = { 4, 10 }, depth = 6 },              -- the tower
          { kind = "flat", x = { 14, 21 }, rows = { 11, 14 } }, -- keys+mouse
          { kind = "flat", x = { 22, 30 }, rows = { 1, 14 } },  -- the paper
        },
      },
      -- F03: the empty north table beside it (OAKS_LAB cell 2,1): the
      -- starter table's band table verbatim on a grid two tiles
      -- narrower.
      {
        id = "lab_table_small",
        tiles = {
          { 41, 59, 59, 42 },
          { 78, 57, 57, 79 },
          { 88, 89, 89, 90 },
        },
        roofRows = 19, roofBack = 16, roofFront = 0, roofCycle = { 2, 13 },
        slab = 3, frontEave = 0, ledge = nil, depth = 2,
      },
    },

    POKECENTER = {
      -- F04: the PC in every Center's northeast corner (11
      -- placements; the Indigo Plateau lobby's twin is registered
      -- under MART below). The lab desk-set read again: a Mac-style
      -- unit drawn face-on -- white top band (rows 0-3), bezel, screen
      -- and drive slot (4-14) -- standing at the back of a low desk
      -- whose front face is rows 20-23; the drawn top around the unit
      -- is WHITE, which is what `lid` carries. The keyboard rows 17-19
      -- are drawn below the desk's 16px top span, so the flat part's
      -- `z` puts it at the desk's front edge. The old billboard pins
      -- for these tiles (66/70/82/86, desk 9/88) stay as the
      -- degradation path -- the claim neutralizes them wherever this
      -- template stamps.
      {
        id = "center_pc",
        tiles = {
          { 66, 70 },
          { 82, 86 },
          {  9, 88 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 2,
        desk = { fascia = { 20, 21 }, base = { 22, 23 }, lid = "white" },
        parts = {
          { kind = "upright", x = { 2, 13 }, top = { 0, 3 },
            facade = { 4, 14 }, depth = 6 },                -- the unit
          { kind = "flat", x = { 2, 13 }, rows = { 17, 19 },
            z = 13 },                                       -- keyboard
        },
      },
      -- F05: the healing machine behind the counter -- two 4x4-tile
      -- variants, 24 placements between them (a pair in every Center,
      -- cells (1,0):(2,1) and (6,0):(7,1), plus the Indigo Plateau
      -- lobby's pair under MART below).  The variants differ only in
      -- the east flank: the west machine has the control keyboard
      -- there (7/13, scan "40,58,59,40;40,74,75,40;72,76,77,7;
      -- 72,6,22,13" -- 12 placements), the east machine mirrored
      -- hoses (73, scan "...;72,76,77,73;72,6,22,73" -- 12).
      --
      -- The FULL drawing is claimed now: the corners are the striped
      -- wall band (40), the flanks the machine's own equipment --
      -- hoses and a keyboard ATTACHED to the cabinet, not furniture
      -- standing free (their standee pins above stay as the
      -- degradation path).  What no class can split is a wall-height
      -- cabinet with a monitor perched on its front top edge, drawn
      -- across two map rows because it towers over the 16px band
      -- behind it, which the volume path can only read as more wall.
      --
      -- Read off the pixels (absolute grid x0..x31):
      --   rows 15-31, x8..x23  the CABINET's front face, 16 wide, 17
      --               tall: black front-top edge with vent notches
      --               (15), white top rail (16), black panel in a
      --               white frame (17-28), white rail / light plinth /
      --               black ground line (29-31).  `desk.x` bounds the
      --               desk to the middle columns.
      --   rows 6-14, x8..x23   the cabinet's TOP FACE seen from above
      --               -- not a second-story facade: a white expanse
      --               with a lit west strip (x9) and a shaded east
      --               strip (x22) wrapping the monitor.  Its 9 rows
      --               plus the front edge row 15 ARE the cabinet's
      --               depth: 10, z 16..25 against the wall.
      --               `desk.top` lays the band flat as the lid; where
      --               the monitor's drawing occludes it, the lid
      --               continues the nearest strip (the drawing's own
      --               pixels).
      --   rows 1-13, x10..x21  the MONITOR: black back rim (1) and
      --               white cap (2-3) seen from above -- depth 4 --
      --               then bezel, screen and control strip (4-13)
      --               face-on, 10 tall, at the cabinet top's front
      --               (the drawn base edge 13 is one band row up from
      --               the front strip 14): z 20..23.  The screen
      --               interior (x13..x18, rows 6-8) sinks one voxel
      --               via `inset` -- the pane rule applied by hand,
      --               because `panes = false` blocks the global pass.
      --   rows 16-31, x0..x7   the HOSES (tile 72 stacked): one 8-row
      --               motif per map row, and the two stacked motifs
      --               are two hoses in DEPTH -- the drawn row band is
      --               the depth band, and each motif's own rows are
      --               its elevation WITHIN that band, exactly the
      --               potted plants' stacked-cell rule.  So both
      --               hoses hug the floor: a horizontal run off the
      --               cabinet's side (rows 24-26, x3..x7 -> heights
      --               5..7) over a shaded drop landing ON the floor
      --               (rows 27-31, x2..x7 -> heights 0..4) -- all
      --               measured, the drawn extent maps 1:1 with no
      --               continuation.  `box` parts at z 18 and z 24, 3
      --               deep; both wear the LOWER motif's rows (the one
      --               drawn at its true elevation; the upper motif is
      --               the same atlas tile, pixel-identical).
      --   rows 16-31, x24..x31 west variant: the KEYBOARD (7/13), a
      --               key grid with its cable at the north end and a
      --               bar down the east edge -- TOP-VIEW art, 16 rows
      --               = 16 depth rows.  A `flat` part mounted on the
      --               cabinet's side at COUNTER level (`at` 8, the
      --               counters' own 8px band -- the one number
      --               top-view art cannot state, pinned to the room's
      --               work surface), 3 thick, top face wearing the
      --               drawn art.  The dark dashes east of it (x30-31)
      --               are its cast shadow on the floor: background.
      --               East variant: mirrored hoses (runs x24..x28,
      --               drops x24..x29), same rows and z slots.
      --   rows 0-15 elsewhere  wall stripes and the machine's cast
      --               shadow -- BACKGROUND, the same standing as the
      --               potted plants' floor.  The `wall` element keeps
      --               the band solid over the back map row, full grid
      --               width: a 16-tall, 16-deep block cycling the
      --               drawing's own stripe unit (x0, rows 0-3), what
      --               the neighbouring cells' wall pins render.
      --
      -- `depth = 4` is BOTH map rows: the back row is the wall's plot,
      -- the front row the machine's own.  `panes = false`: the front
      -- panel seals DARK behind LIGHT (a black panel in a white
      -- frame), the opposite polarity to the pane rule, so the global
      -- recess pass would sink the frame and leave the panel proud.
      {
        id = "center_heal_machine_w",
        tiles = {
          { 40, 58, 59, 40 },
          { 40, 74, 75, 40 },
          { 72, 76, 77,  7 },
          { 72,  6, 22, 13 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 4,
        panes = false,
        wall = { h = 16, depthPx = 16, x = 0, cycle = { 0, 3 } },
        desk = { x = { 8, 23 }, fascia = { 15, 16 }, base = { 17, 31 },
                 z = 16, depthPx = 10, top = { 6, 14 } },
        parts = {
          { kind = "upright", x = { 10, 21 }, top = { 1, 3 },
            facade = { 4, 13 }, z = 20, depth = 4,
            inset = { x = { 13, 18 }, rows = { 6, 8 } } },   -- the monitor
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 18, depth = 3 },                             -- N hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 18, depth = 3 },                             -- N hose drop
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 24, depth = 3 },                             -- S hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 24, depth = 3 },                             -- S hose drop
          { kind = "flat", x = { 24, 29 }, rows = { 16, 31 },
            z = 16, at = 8, thick = 3 },                     -- keyboard shelf
        },
      },
      {
        id = "center_heal_machine_e",
        tiles = {
          { 40, 58, 59, 40 },
          { 40, 74, 75, 40 },
          { 72, 76, 77, 73 },
          { 72,  6, 22, 73 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 4,
        panes = false,
        wall = { h = 16, depthPx = 16, x = 0, cycle = { 0, 3 } },
        desk = { x = { 8, 23 }, fascia = { 15, 16 }, base = { 17, 31 },
                 z = 16, depthPx = 10, top = { 6, 14 } },
        parts = {
          { kind = "upright", x = { 10, 21 }, top = { 1, 3 },
            facade = { 4, 13 }, z = 20, depth = 4,
            inset = { x = { 13, 18 }, rows = { 6, 8 } } },   -- the monitor
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 18, depth = 3 },                             -- NW hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 18, depth = 3 },                             -- NW hose drop
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 24, depth = 3 },                             -- SW hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 24, depth = 3 },                             -- SW hose drop
          { kind = "box", x = { 24, 28 }, rows = { 24, 26 },
            z = 18, depth = 3 },                             -- NE hose run
          { kind = "box", x = { 24, 29 }, rows = { 27, 31 },
            z = 18, depth = 3 },                             -- NE hose drop
          { kind = "box", x = { 24, 28 }, rows = { 24, 26 },
            z = 24, depth = 3 },                             -- SE hose run
          { kind = "box", x = { 24, 29 }, rows = { 27, 31 },
            z = 24, depth = 3 },                             -- SE hose drop
        },
      },
    },

    MART = {
      -- F04 again: the Indigo Plateau lobby's PC (cell 15,7) -- the
      -- MART tileset shares the POKECENTER atlas, so this is the same
      -- drawing tile for tile. Same part table as the POKECENTER entry
      -- above.
      {
        id = "center_pc",
        tiles = {
          { 66, 70 },
          { 82, 86 },
          {  9, 88 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 2,
        desk = { fascia = { 20, 21 }, base = { 22, 23 }, lid = "white" },
        parts = {
          { kind = "upright", x = { 2, 13 }, top = { 0, 3 },
            facade = { 4, 14 }, depth = 6 },                -- the unit
          { kind = "flat", x = { 2, 13 }, rows = { 17, 19 },
            z = 13 },                                       -- keyboard
        },
      },
      -- F05 again: the Indigo Plateau lobby has the Centers' healing
      -- machine pair too -- the west-variant grid at (5,4):(6,5) and
      -- the east at (10,4):(11,5), verified by region dump -- and its
      -- MART tileset shares the POKECENTER atlas, so these are the
      -- same drawings tile for tile. Same part tables as the
      -- POKECENTER entries above.
      {
        id = "center_heal_machine_w",
        tiles = {
          { 40, 58, 59, 40 },
          { 40, 74, 75, 40 },
          { 72, 76, 77,  7 },
          { 72,  6, 22, 13 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 4,
        panes = false,
        wall = { h = 16, depthPx = 16, x = 0, cycle = { 0, 3 } },
        desk = { x = { 8, 23 }, fascia = { 15, 16 }, base = { 17, 31 },
                 z = 16, depthPx = 10, top = { 6, 14 } },
        parts = {
          { kind = "upright", x = { 10, 21 }, top = { 1, 3 },
            facade = { 4, 13 }, z = 20, depth = 4,
            inset = { x = { 13, 18 }, rows = { 6, 8 } } },   -- the monitor
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 18, depth = 3 },                             -- N hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 18, depth = 3 },                             -- N hose drop
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 24, depth = 3 },                             -- S hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 24, depth = 3 },                             -- S hose drop
          { kind = "flat", x = { 24, 29 }, rows = { 16, 31 },
            z = 16, at = 8, thick = 3 },                     -- keyboard shelf
        },
      },
      {
        id = "center_heal_machine_e",
        tiles = {
          { 40, 58, 59, 40 },
          { 40, 74, 75, 40 },
          { 72, 76, 77, 73 },
          { 72,  6, 22, 73 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 4,
        panes = false,
        wall = { h = 16, depthPx = 16, x = 0, cycle = { 0, 3 } },
        desk = { x = { 8, 23 }, fascia = { 15, 16 }, base = { 17, 31 },
                 z = 16, depthPx = 10, top = { 6, 14 } },
        parts = {
          { kind = "upright", x = { 10, 21 }, top = { 1, 3 },
            facade = { 4, 13 }, z = 20, depth = 4,
            inset = { x = { 13, 18 }, rows = { 6, 8 } } },   -- the monitor
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 18, depth = 3 },                             -- NW hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 18, depth = 3 },                             -- NW hose drop
          { kind = "box", x = { 3, 7 }, rows = { 24, 26 },
            z = 24, depth = 3 },                             -- SW hose run
          { kind = "box", x = { 2, 7 }, rows = { 27, 31 },
            z = 24, depth = 3 },                             -- SW hose drop
          { kind = "box", x = { 24, 28 }, rows = { 24, 26 },
            z = 18, depth = 3 },                             -- NE hose run
          { kind = "box", x = { 24, 29 }, rows = { 27, 31 },
            z = 18, depth = 3 },                             -- NE hose drop
          { kind = "box", x = { 24, 28 }, rows = { 24, 26 },
            z = 24, depth = 3 },                             -- SE hose run
          { kind = "box", x = { 24, 29 }, rows = { 27, 31 },
            z = 24, depth = 3 },                             -- SE hose drop
        },
      },
    },

    GYM = {
      -- F02 again: the Hall of Fame's recording machine is the lab's
      -- computer desk drawing, tile for tile, on the GYM atlas (one
      -- placement: HALL_OF_FAME cell 4,1). Same part table as the DOJO
      -- entry above.
      {
        id = "lab_computers",
        tiles = {
          { 91, 92, 93, 94 },
          { 54, 55, 85, 95 },
          { 88, 89, 89, 90 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 2,
        desk = { fascia = { 16, 18 }, base = { 19, 21 } },
        parts = {
          { kind = "upright", x = { 2, 13 }, top = { 0, 2 },
            facade = { 3, 10 }, depth = 4 },              -- the monitor
          { kind = "flat", x = { 1, 13 }, rows = { 11, 14 } },  -- keyboard
          { kind = "upright", x = { 14, 21 }, top = { 0, 3 },
            facade = { 4, 10 }, depth = 6 },              -- the tower
          { kind = "flat", x = { 14, 21 }, rows = { 11, 14 } }, -- keys+mouse
          { kind = "flat", x = { 22, 30 }, rows = { 1, 14 } },  -- the paper
        },
      },
    },

    CLUB = {
      -- F06: the Bike Shop's OPEN TOOLBOX -- BIKE_SHOP cells (6,6) and
      -- (7,7), and nowhere else in the game (2 placements).
      --
      -- The drawing looks down INTO the box: what fills its middle is not
      -- a face but the inside of the tray, with a wrench lying in it, and
      -- the lid standing open on the right.  That is why every solid
      -- treatment fails it.  As a `billboard` (what these tiles carried)
      -- the whole 16x16 went up as one 10-voxel per-pixel slab -- the
      -- extruded picture in its pure form, a black monolith wearing the
      -- drawing as a decal.  Reading the middle as a cabinet FRONT and
      -- extruding that is the same mistake one level down: it puts a wall
      -- where the opening is.  An open box has to be hollow, so `tray`
      -- builds four walls, a floor slab and AIR between them.
      --
      -- The bands, and they measure out exactly (8 depth rows for a
      -- one-tile-row plot):
      --   row 4       the FAR rim, black across the back wall     -> z 0
      --   rows 5-10   the tray's inside, seen from above, with the
      --               wrench lying across it -- drawn row = depth row,
      --               six rows for six rows                       -> z 1-6
      --   row 11      the near wall's INNER face, in shadow
      --   row 12      the near rim, black right across the box    -> z 7
      --   rows 13-15  the near wall's outer face, seen face-on: a light
      --               panel between its black rim and its black foot,
      --               so the wall stands 4 voxels and the rim is its top
      --
      -- `x` is the box's outer span and `inner` the opening's, so the
      -- one-column difference on each side IS the wall.  x12 is left out
      -- of both on purpose: the #555 at x11-x12 on rows 13-15 is the 3/4
      -- shear of the right wall, which un-projecting simply removes --
      -- the wall is where the plan says it is, not where the projection
      -- slides it to.  `floor = 0` puts the tray's bottom one voxel thick,
      -- leaving three voxels of open box above it.
      --
      -- The LID is an upright part riding the rim, hinged on the right
      -- and standing up: 12 tall as drawn, spanning the box's whole depth
      -- (8) and 4 thick, which is the black outline plus the two columns
      -- of white body the drawing gives it.  It overhangs east of the
      -- hinge, which is what a hinged lid standing open does.
      {
        id = "bike_shop_toolbox",
        tiles = {
          { 29, 13 },
          { 21, 22 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depthPx = 14,
        tray = { top = { 4, 11 }, front = { 12, 15 }, x = { 2, 11 },
                 inner = { 3, 9 }, floor = 0 },
        parts = {
          { kind = "upright", x = { 11, 14 }, top = { 0, 0 },
            facade = { 0, 11 }, z = 0, depth = 14 },       -- the open lid
        },
      },
    },

    MANSION = {
      -- F05: the TALL display cabinet, the one with the trophy behind
      -- its glass -- CELADON_CHIEF_HOUSE cells 3,0 and 4,0 and
      -- CELADON_MANSION_1F cell 2,2 (3 placements).  Its 32 rows read
      -- like every band table's: 0-8 the cabinet top seen from above
      -- (black rim, white highlight courses along the north and west,
      -- grey field, the front corner shaded at row 8); row 9 the top's
      -- own black front edge -- which is what the rim treatment paints,
      -- so slab = 1 and that row folds into the roof band instead of
      -- extruding under it; 10-31 the front face: the trophy in its
      -- dark display opening, the nameplate under it, then the two
      -- panelled doors of the base.  The contents come off the pixels,
      -- not the band table: the trophy, the plate and both door panels
      -- are non-black regions the drawing seals behind its own black
      -- frame, so the measured recess pass sinks each of them a voxel
      -- and the frames stay proud.  Nine drawn top rows over a 32px
      -- plot, so the rims map 1:1 -- the drawn front-corner shading
      -- lands one voxel behind the front edge -- and the uniform field
      -- cycles between.  Both cell rows of the plot are BLOCKED and
      -- both are cabinet drawing, so D is the whole grid: the rank is
      -- built into the room's north wall, and its front stands flush
      -- with the short case's beside it.  23 voxels tall.
      {
        id = "mansion_trophy_case",
        tiles = {
          { 38, 41 },
          { 40, 21 },
          { 56, 87 },
          { 50, 51 },
        },
        roofRows = 10, roofBack = 8, roofFront = 2, roofCycle = { 2, 7 },
        slab = 1, frontEave = 0, ledge = nil,
      },
      -- F06: the SHORT book case standing beside it -- the same
      -- cabinet on a grid one tile row shorter (CELADON_CHIEF_HOUSE
      -- cells 2,0 and 5,0, CELADON_MANSION_1F tiles 2,5 and 6,5; 4
      -- placements).  Identical top band, identical panelled base;
      -- only the display opening is shorter, a shelf of books where
      -- the tall one has the trophy.  Same band numbers as F05 --
      -- which is what makes the pair read as one line of furniture --
      -- and 15 voxels tall against the tall one's 23, exactly the 8
      -- rows of drawing between them.  The grid must carry the 38/41
      -- cap row: {34,35} over {50,51} alone also stands on
      -- CELADON_MANSION_2F, where it is the bottom of a taller
      -- two-shelf bank and not this drawing at all.  The 8px of wall
      -- behind the cap is not part of the cabinet and keeps its own
      -- `wall` pin.
      {
        id = "mansion_bookcase",
        tiles = {
          { 38, 41 },
          { 34, 35 },
          { 50, 51 },
        },
        roofRows = 10, roofBack = 8, roofFront = 2, roofCycle = { 2, 7 },
        slab = 1, frontEave = 0, ledge = nil,
      },
      -- F07: the long table in the middle of the chief's house
      -- (CELADON_CHIEF_HOUSE cell 2,3), the lab table's read at four
      -- cells wide and two deep.  Rows 0-23 are the tabletop seen from
      -- above; 24-26 are the top slab's own front edge,
      -- black/#555/black, and row 27 the #555 shadow that closes it --
      -- exactly what the rim treatment paints, so slab = 3 and rows
      -- 24-27 fold into the roof band.  That leaves 28-30 as the base,
      -- the same three rows the lab table's is, and the two tables
      -- stand the same 6 voxels: row 28 the apron running the whole
      -- width, 29-30 the end legs under it.  The legs stop one row
      -- short of the grid, so the measured ground line lands there and
      -- the model does not float.  Both cell rows of the plot are
      -- blocked, so D is the whole grid: the 24 drawn top rows map 1:1
      -- from the north rim and the field's own rows cycle for the last
      -- 8.  The `table` pin these tiles keep stays 12px -- it is
      -- shared with the 2F/3F writing desks and the rooftop shed, and
      -- nothing rides this table -- so it is only the degradation
      -- path, neutralized wherever this template stamps.
      {
        id = "mansion_long_table",
        tiles = {
          { 38, 39, 39, 39, 39, 39, 39, 41 },
          { 54, 55, 55, 55, 55, 55, 55, 57 },
          { 54, 55, 55, 55, 55, 55, 55, 57 },
          { 60, 58, 58, 58, 58, 58, 58, 59 },
        },
        roofRows = 28, roofBack = 24, roofFront = 0, roofCycle = { 2, 23 },
        slab = 3, frontEave = 0, ledge = nil,
      },
    },

    HOUSE = {
      -- F08: the dining table of the generic town house -- 18
      -- placements, every home's cells (3,3):(4,4), Blue's and the
      -- Daycare among them -- the chief's long table (F07 above) at two
      -- cells wide, the same read to the row.  Rows 0-23 are the rounded
      -- tabletop seen from above (black rim, white highlight course,
      -- grey field, #555 east rim); 24-26 the slab's own front edge,
      -- black/#555/black, and 27 the #555 apron shadow that closes it,
      -- folded into the band; 28-30 the base -- the apron's black
      -- underrun and the corner legs -- stopping one row short of the
      -- grid, so the measured ground line keeps the model on its plot.
      -- The same 6 voxels the whole table family stands.  The `table`
      -- pins stay as the degradation path, neutralized where this
      -- stamps; the schoolhouse's half-width table with its book and the
      -- trashed house's ransacked corner are different grids and keep
      -- theirs.
      {
        id = "house_table",
        tiles = {
          { 38, 39, 39, 41 },
          { 54, 47, 47, 57 },
          { 54, 47, 47, 57 },
          { 60, 58, 58, 59 },
        },
        roofRows = 28, roofBack = 24, roofFront = 0, roofCycle = { 2, 23 },
        slab = 3, frontEave = 0, ledge = nil,
      },
      -- F10: the town house's BOOKCASE -- the commonest piece of
      -- furniture in the game at 58 placements across three drawings,
      -- and the piece this family was really for: pinned `desk` it was a
      -- 24px box with a flat front and the books PAINTED on it.  Band for
      -- band it is the Celadon display cabinet (F05/F06 under MANSION)
      -- on a different atlas, and it takes those numbers unchanged: rows
      -- 0-8 the top seen from above (black rim, white highlight courses
      -- along the north and west, grey field, the front corner shaded at
      -- row 8); row 9 the top's own black front edge -- which is what the
      -- rim treatment paints, so slab = 1 and that row folds into the
      -- roof band instead of extruding under it; 10-31 the front: two
      -- shelves in their dark openings over the cupboard's two panelled
      -- doors.  Every book, bowl and door panel is a non-black region the
      -- drawing seals behind its own black frame, so the measured pane
      -- pass sinks each one a voxel and the frames stand proud of them --
      -- the relief the `bookcase` class now carries too, arrived at the
      -- same way.
      --
      -- Nine drawn top rows over a 32px plot: the rims map 1:1 (the drawn
      -- front-corner shading lands one voxel behind the front edge) and
      -- the uniform field cycles between.  BOTH cell rows of the plot are
      -- blocked and both are cabinet drawing, so D is the whole grid --
      -- the case is built into the room's north wall.  23 voxels tall,
      -- one under the `desk` pin it replaces and exactly the Celadon
      -- trophy case's stand; the `desk` pins stay as the degradation
      -- path, neutralized wherever this stamps.
      --
      -- This drawing carries books and a bowl on each shelf: 36
      -- placements, the west end of eighteen homes.
      {
        id = "house_bookcase_bowls",
        tiles = {
          { 38, 41 },
          { 14, 15 },
          { 14, 15 },
          { 30, 31 },
        },
        roofRows = 10, roofBack = 8, roofFront = 2, roofCycle = { 2, 7 },
        slab = 1, frontEave = 0, ledge = nil,
      },
      -- F10 again: its twin at the east end, books on both shelves -- 22
      -- placements, and the only one of the two that Cerulean's trashed
      -- house also puts at the west end.
      {
        id = "house_bookcase_books",
        tiles = {
          { 38, 41 },
          { 48, 49 },
          { 48, 49 },
          { 30, 31 },
        },
        roofRows = 10, roofBack = 8, roofFront = 2, roofCycle = { 2, 7 },
        slab = 1, frontEave = 0, ledge = nil,
      },
      -- F09: the stool at every one of those tables (94 placements on
      -- this tileset) -- the first template with NO base piece.  The
      -- drawing is one object, a round seat on legs, drawn MID-CELL over
      -- its own floor (rows 0-4 are the room behind it), and no band
      -- split fits that: a roof band starts at the drawing's top row.
      -- So it is a desk-set of exactly one upright part anchored to the
      -- floor: rows 5-10 the seat seen from above (its lid), row 11 the
      -- seat's own front edge, 12-15 the legs with the floor showing
      -- between them, which the per-pixel facade cut keeps open.  The
      -- drawing measures 7 deep (six seat rows plus the front edge at
      -- drawn row = depth row); the shipped stool is grown two voxels
      -- past that north AND south (z 3..13, developer-tuned against the
      -- in-game read), with `stretch` mapping the seat band over the
      -- deeper lid instead of smearing its last row.  `panes = false`:
      -- a stool has no windows, and the pane rule would sink the legs'
      -- lit faces behind their own outlines.  The 5-voxel stand is the
      -- drawn elevation, and the tileset's `heights` above pins the
      -- `stool` ride height to it, so whoever sits here sits ON the
      -- seat; the old stool standee pins stay as the degradation path.
      {
        id = "house_stool",
        tiles = {
          { 2, 3 },
          { 18, 19 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil,
        panes = false,
        parts = {
          { kind = "upright", x = { 2, 13 }, top = { 5, 10 },
            facade = { 11, 15 }, z = 3, depth = 11,
            stretch = true },                             -- the stool
        },
      },
    },

    REDS_HOUSE_1 = {
      -- F08 again: Red's and the Copycat's ground-floor dining table
      -- (cells (3,4):(4,5) of both maps) -- the house table on the
      -- reds_house atlas, with two differences the fields absorb.
      --
      -- Its tabletop field stops at row 22 and row 23 is the top's own
      -- #555 south rim, which roofBack = 24 would lay MID-TABLE as a
      -- dark stripe: back stops at 23 and the field cycles from there
      -- (the drawn rim's place at the south edge is under the rim
      -- treatment's own black, like every sibling's).
      --
      -- And the POTTED PLANT is drawn standing on the tabletop (rows
      -- 5-15, x10..x21, tiles 40/55/56 with the cutout pool's 54/57
      -- beside them).  It stays the cutout standee it has always been:
      -- `keep` leaves its tiles unclaimed so the pin and its standee
      -- survive, `scrub` replaces its pixels with the field shade so the
      -- model tops out as the plain surface it sits on, and `support`
      -- states the model's 6-voxel top plane so the standee stands ON
      -- the modelled tabletop (Structures reads it off the claim; a
      -- plain claim's h = 0 supports nothing).
      {
        id = "reds_house_table",
        tiles = {
          { 38, 39, 40, 41 },
          { 54, 55, 56, 57 },
          { 44, 42, 42, 43 },
          { 60, 58, 58, 59 },
        },
        roofRows = 28, roofBack = 23, roofFront = 1, roofCycle = { 2, 22 },
        slab = 3, frontEave = 0, ledge = nil,
        scrub = { { 10, 5, 21, 15 } },
        keep = { 40, 54, 55, 56, 57 },
        support = 6,
      },
      -- F10 again: Red's and the Copycat's bookcase pair, cells (0,0)
      -- and (1,0) of both maps (4 placements).  The same object as the
      -- town house's, one shelf of each of its two drawings -- 48/49
      -- books above, 34/35 below -- and the same band numbers; see HOUSE
      -- above for the read.
      {
        id = "reds_bookcase",
        tiles = {
          { 38, 41 },
          { 48, 49 },
          { 34, 35 },
          { 50, 51 },
        },
        roofRows = 10, roofBack = 8, roofFront = 2, roofCycle = { 2, 7 },
        slab = 1, frontEave = 0, ledge = nil,
      },
      -- F09 again: the stools around it (10 placements across Red's and
      -- the Copycat's ground floors), pixel for pixel the house
      -- tileset's drawing.  Same part table; see HOUSE above.
      {
        id = "house_stool",
        tiles = {
          { 2, 3 },
          { 18, 19 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil,
        panes = false,
        parts = {
          { kind = "upright", x = { 2, 13 }, top = { 5, 10 },
            facade = { 11, 15 }, z = 3, depth = 11,
            stretch = true },                             -- the stool
        },
      },
    },

    INTERIOR = {
      -- F0x: Bill's desk, and the Silph president's -- one drawing, two
      -- placements (BILLS_HOUSE cell 1,4 and SILPH_CO_11F cell 10,12,
      -- both found by the scan and nothing else).  The whole 4x4-tile
      -- block is one designed unit, but this template deliberately takes
      -- only the desk's own two cells.
      --
      -- What the 16 drawn rows are: the TABLETOP seen from above, the
      -- lab table's pattern tile for tile -- black rim, a white
      -- highlight course inside it, grey field -- over a 16px plot, so
      -- they map 1:1 and nothing cycles.  Standing on it, and drawn INTO
      -- that top view the way lab_computers' objects are: a terminal
      -- (screen head over a keypad panel, rows 3-13) and the ball
      -- (rows 1-13).  Drawn row = depth row on a top view, so each part's
      -- `z` is where the drawing puts it: the head's front row is 8, the
      -- keypad picks up at 9, and the ball's front row is its drawn
      -- bottom.  Only the two DEPTHS and how much of each blob is lid
      -- rather than face are authored -- the projection cannot state
      -- either.
      --
      -- Why the grid stops at two rows.  This drawing's front face is its
      -- APRON, and the artist drew the apron into the WALKABLE cell in
      -- front (43/44 + 91/92) -- exactly where the lab table's fascia and
      -- base are.  But 43/44 is also the upper half of the CHAIR pushed
      -- up to the desk (43/44 over 59/60, pinned `stool` in the tileset
      -- section above), and a template claims whole TILES: reading the
      -- apron would take the chair's back with it and leave a backless
      -- stub in both rooms.  So the apron stays with the chair, `plane`
      -- authors the desk's height instead, and the body under the lid is
      -- synthesized in the drawing's own shades (the band table's rim
      -- treatment -- a shaded box closed by the outline at the floor).
      -- 8px is not a taste number: it is the apron's own drawn row count
      -- and the `table` height these tiles are already pinned to, so the
      -- desk stands where the degradation path stood it.
      {
        id = "bills_desk",
        tiles = {
          { 11, 12, 13, 14 },
          { 27, 28, 29, 30 },
          { 43, 44, 91, 92 },
          { 59, 60, 31, 31 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil, depth = 4,
        -- the desk's own plot is its two cells; the grid runs on because
        -- its apron and the CHAIR share tiles 43/44
        desk = { fascia = { 16, 18 }, base = { 19, 23 }, depth = 2 },
        parts = {
          -- the notes: two sheets lying on the desk, so PAPER -- one
          -- voxel proud at drawn row = depth row, and nothing raised
          { kind = "flat", x = { 2, 15 }, rows = { 3, 7 } },
          -- the keyboard: a real slab, not a print on the desk.  Its
          -- keys are drawn from ABOVE so they ride the top face across
          -- its depth, and its drawn bottom frame row stands as the
          -- front edge
          { kind = "upright", x = { 4, 15 }, top = { 8, 12 },
            facade = { 12, 13 }, z = 8, depth = 6 },
          -- the cord: the kinked dark run the drawing puts between the
          -- keyboard's top-right corner and the computer's left corner.
          -- Raised to the keyboard's own height so it reads as a cable
          -- spanning them rather than a scuff on the desk
          { kind = "upright", x = { 16, 19 }, top = { 8, 8 },
            facade = { 8, 9 }, z = 8, depth = 2 },
          -- the computer: drawn in 2:1 ISOMETRIC, turned 45 degrees to
          -- the map -- see the `iso` branch in buildParts.  `plan` = rx
          -- makes its footprint a SQUARE turned 45, so from directly
          -- above it is the cube the drawing depicts and not the slab
          -- the 2:1 would otherwise build
          { kind = "iso", x = { 19, 30 }, rows = { 1, 13 },
            plan = 6, z = 9 },
          -- the chair pushed up to the desk, drawn into the walkable
          -- cell in front.  It stands on the FLOOR, not on the desk, so
          -- its rise is the whole plane back down; two voxels deep
          -- because it is a chair, and `inside` cuts it per pixel, so
          -- this is the thin slab the `stool` standee was -- the desk
          -- claiming tiles 43/44 for its apron is what makes the
          -- template owe it
          { kind = "upright", x = { 2, 13 }, top = { 20, 21 },
            facade = { 22, 31 }, rise = -8, z = 22, depth = 10 },
        },
      },
      -- F09 once more: the Pokemon Fan Club's four members' chairs,
      -- drawn round the boardroom table -- POKEMON_FAN_CLUB cells (1,3),
      -- (1,4), (6,3) and (6,4), and nowhere else in the game.
      --
      -- A DIFFERENT drawing from the house stool -- its seat field
      -- carries a one-pixel white margin where the house's carries two
      -- -- but the same object band for band: rows 5-10 the seat seen
      -- from above (its lid), row 11 the seat's own front edge, 12-15
      -- the legs with the floor showing between them.  Its elevation
      -- rows are PIXEL-IDENTICAL to the house drawing's, so it takes
      -- that part table unchanged, growth and all: z 3..13, `stretch`
      -- mapping the seat band over the deeper lid, `panes = false` so
      -- the pane rule does not sink the legs' lit faces.
      --
      -- Rows 11-15 come from tiles 59/60, which this drawing SHARES
      -- with Bill's chair (43/44 over 59/60, modelled as a part of
      -- `bills_desk` above).  That is why the tileset's `stool = 5`
      -- height override is right for both seats rather than a special
      -- case for this one: they are drawn at the same height because
      -- they are drawn with the same pixels.
      --
      -- Listed after `bills_desk` although neither grid is a subgrid of
      -- the other (that grid has 43/44 over 59/60, this one 61/62), so
      -- the order is free and the bigger, more specific grid keeps
      -- first claim.
      {
        id = "club_stool",
        tiles = {
          { 61, 62 },
          { 59, 60 },
        },
        roofRows = 0, roofBack = 0, roofFront = 0, roofCycle = { 0, 0 },
        slab = 0, frontEave = 0, ledge = nil,
        panes = false,
        parts = {
          { kind = "upright", x = { 2, 13 }, top = { 5, 10 },
            facade = { 11, 15 }, z = 3, depth = 11,
            stretch = true },                             -- the stool
        },
      },
    },
  },
}

-- ---------------------------------------------------------------------------
-- TilesetJohtoModern -- the set Goldenrod City and Azalea Town are drawn in.
--
-- The ROM names it separately from TilesetJohto, and the profile is keyed by
-- the tileset id, so those two maps were reaching NO pins and NO buildings at
-- all: every scrap of turf sharing a blocked cell stood as a 16px box, the
-- ledges and the picket fences stood as walls, the town signs stood as
-- masonry, and every house was a flat-lidded slab with its roof printed on
-- the top face.  That is exactly what "messed up in goldenrod, azalea town"
-- describes.
--
-- Comparing the two atlases tile for tile: 66 of 96 are byte-identical, and
-- every tile the pins and the building templates below name is among them --
-- ground $05/$06, water $14/$58, the ledge lip $4C, the fence run
-- $40/$4A/$59/$5A, the signpost $4E/$4F/$5E/$5F, the tree $1E/$1F/$3E/$3F,
-- the cliff context $3C/$4B/$4D, and the whole roof/facade vocabulary
-- $01/$02/$07/$0A-$0F/$10-$12/$16-$19/$1A-$1C/$23/$24/$26/$37-$3A.  So the
-- authored work transplants unchanged.
--
-- The one thing that does NOT transplant is the tall tree WALL.  Johto draws
-- it as a crown over a middle course over an underside ($1E/$1F, $2E/$2F,
-- $3E/$3F) and pins the middle course as `planter` to get its two-cell
-- height.  In Modern $2E/$2F are different art entirely and appear in no
-- tree: scanning all 128 blocks, the only thing ever drawn under $1E/$1F is
-- $3E/$3F (eleven blocks) or $13/$15 (two blocks).  Modern has no tall tree,
-- only the one-cell lone tree -- which the `cylinder` pin already rounds --
-- so the planter pin and the conditional that arms it are left out.
profile.tilesets.TilesetJohtoModern = {
  ground = { 0x05, 0x06 },
  water = { 0x14, 0x58 },
  -- the plateau top, transplanted with the rest of the terrain vocabulary
  -- (see TilesetJohto's `terrace`).  Modern has far less of it -- Azalea's
  -- north verge and one lip cell in Goldenrod -- but it is the same
  -- drawing in the same ids, and left out those few cells would have been
  -- the only flat terraces in Johto
  terrace = { 0x2C, 0x3C },
  ledge = { 0x4C },
  post = { 0x4A, 0x59, 0x5A },
  flower = { 0x03 },
  signpost = { 0x4E, 0x4F, 0x5E, 0x5F },
  cylinder = { 0x1E, 0x1F, 0x3E, 0x3F },
  when_above = {
    [0x4C] = { { above = { 0x3C, 0x4B, 0x4C, 0x4D }, class = "wall" } },
  },
}

-- Goldenrod's own buildings, the ones Johto's catalogue has no drawing for.
-- Each was read straight off GOLDENROD_CITY's tile grid, as the region left
-- over once every Johto template had claimed what it matches.
--
-- They share Johto's roof exactly -- black ridge, white highlight, the
-- stripe field, a four-row fascia -- so `roofRows` 32 / `roofBack` 2 /
-- `roofFront` 4 / `roofCycle` { 2, 27 } carry over verbatim; what differs is
-- the footprint and the facade.
profile.buildings.TilesetJohtoModern = {
  -- THE RADIO TOWER, and it comes before even the department store.  Twelve
  -- cells of identical window course is exactly the repeat the volume path's
  -- trim-foot rule reads as a 16px pattern, so the city's landmark was
  -- pressed flat into its own pavement the way Olivine's lighthouse was.
  --
  -- It is drawn as TWO stepped shafts side by side, the west one six cells
  -- taller than the east.  The rectangle that would hold both also holds the
  -- cottage and the pavement standing north of the east shaft -- cells this
  -- must not claim -- so it is two templates split down the seam between the
  -- shafts.  Each seals the cut side (`e` on the west, `w` on the east):
  -- the drawing runs straight on across it, and without the seal the
  -- silhouette flood walks in through the window courses and hollows the
  -- tower out.  Each half still carries its own height, so the west shaft
  -- rises past the east one just as the art shows.
  {
    id = "goldenrod_radio_tower_west",
    tiles = {
      { 0x2E, 0x56, 0x42, 0x43 },
      { 0x50, 0x30, 0x33, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x50, 0x26, 0x26, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x50, 0x26, 0x26, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x50, 0x26, 0x26, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x50, 0x26, 0x26, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x50, 0x26, 0x26, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x50, 0x26, 0x26, 0x53 },
      { 0x50, 0x21, 0x1D, 0x21 },
      { 0x50, 0x26, 0x26, 0x26 },
      { 0x50, 0x21, 0x1D, 0x21 },
      { 0x50, 0x26, 0x26, 0x26 },
      { 0x50, 0x21, 0x1D, 0x21 },
      { 0x50, 0x26, 0x26, 0x26 },
      { 0x50, 0x21, 0x1D, 0x21 },
      { 0x50, 0x53, 0x35, 0x35 },
      { 0x50, 0x53, 0x35, 0x35 },
      { 0x20, 0x25, 0x06, 0x06 },
    },
    -- the cap is two tile rows -- the black crown and the dish standing on
    -- it -- so a 16px band with no eave: this is a flat modern roof, not
    -- one of Johto's gables.
    roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
    slab = 4, frontEave = 0, ledge = nil,
    seal = "e",
  },
  -- the east shaft, topping out six cells lower with its own dish
  {
    id = "goldenrod_radio_tower_east",
    tiles = {
      { 0x2E, 0x56, 0x42, 0x43 },
      { 0x1D, 0x30, 0x33, 0x53 },
      { 0x1D, 0x21, 0x1D, 0x53 },
      { 0x26, 0x26, 0x26, 0x53 },
      { 0x1D, 0x21, 0x1D, 0x53 },
      { 0x26, 0x26, 0x26, 0x53 },
      { 0x1D, 0x21, 0x1D, 0x53 },
      { 0x26, 0x26, 0x26, 0x53 },
      { 0x1D, 0x21, 0x1D, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x50, 0x21, 0x1D, 0x53 },
      { 0x20, 0x21, 0x1D, 0x25 },
    },
    roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
    slab = 4, frontEave = 0, ledge = nil,
    seal = "w",
  },
  -- the department store: six cells wide and EIGHT cells tall, storey
  -- bands of window ($26) every three courses.  It has to come first --
  -- first claim wins, and the smaller blocks below would otherwise take
  -- bites out of its facade and stand second buildings through it.
  {
    id = "goldenrod_dept_store",
    tiles = {
      { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x26, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x37, 0x38, 0x07, 0x07, 0x18, 0x19, 0x07, 0x1C },
      { 0x01, 0x02, 0x02, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x17, 0x17, 0x02, 0x16 },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the six-cell plaster hall with a bay at each end and a central door:
  -- Johto's `johto_hall` drawn in $07 render instead of $1B brick
  {
    id = "goldenrod_hall_plain",
    tiles = {
      { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x26, 0x26, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x37, 0x38, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x01, 0x02, 0x02, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the same hall with its door at the west end and one bay at the east
  {
    id = "goldenrod_hall_plain_w",
    tiles = {
      { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x26, 0x26, 0x1C },
      { 0x1A, 0x07, 0x37, 0x38, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x01, 0x02, 0x39, 0x3A, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- doorless four-cell blocks with a bay at each end, plaster and brick:
  -- the city's back-lot warehouses
  {
    id = "goldenrod_block_plain_2bay",
    tiles = {
      { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x1A, 0x26, 0x26, 0x07, 0x07, 0x26, 0x26, 0x1C },
      { 0x1A, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x1C },
      { 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  {
    id = "goldenrod_block_brick_2bay",
    tiles = {
      { 0x10, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x12 },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0x0F },
      { 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0C },
      { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
      { 0x1A, 0x26, 0x26, 0x1B, 0x1B, 0x26, 0x26, 0x1C },
      { 0x1A, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1C },
      { 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x16 },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
}

-- ...then Johto's own catalogue behind them. Every drawing it names is cut
-- from tiles Modern shares byte for byte, and Azalea's Mart, Centre, gym and
-- cottages and Goldenrod's Centre, gym and terraces are those drawings
-- exactly -- matched against both maps' tile grids before this was written.
-- Order is priority order (first claim wins), so the city-specific templates
-- above get their cells first.
for _, template in ipairs(profile.buildings.TilesetJohto) do
  profile.buildings.TilesetJohtoModern[#profile.buildings.TilesetJohtoModern + 1]
    = template
end

-- ---------------------------------------------------------------------------
-- TilesetKanto -- the set the whole of Kanto is drawn in, 39 maps, the
-- largest single gap left after JohtoModern and the same failure: no pins at
-- all, so every ledge, every fence run and every tree came out as a 16px
-- wall.
--
-- Nothing transplants from Johto: comparing the two atlases only three of 96
-- tiles match, and none of them is one the Johto pins name.  Every group
-- below was read off Kanto's own 128 blocks -- the tile quad that fills each
-- 16x16 cell, counted across the whole blockset, cross-checked against the
-- collision class the cell carries.
profile.tilesets.TilesetKanto = {
  -- the two turf drawings the ledge classes ($A0-$A5) themselves sit on --
  -- $2C the dappled grass (51 cells) and $39 the sparse one (20) -- plus the
  -- pavement $23/$11/$10/$30 that the towns' forecourts are paved with.  All
  -- are walkable, so they would already fall to "ground"; naming them keeps
  -- them flat where they run into a blocked cell, which is where the
  -- fallback would otherwise raise them.
  ground = { 0x10, 0x11, 0x23, 0x2C, 0x30, 0x39 },
  -- class $29 is Kanto's water, and these four are the only tiles ever drawn
  -- in one: $14 the open surface, $33 and $31 the shore courses, $54 the
  -- ripple.
  water = { 0x14, 0x31, 0x33, 0x54 },
  -- the hop-down lip.  As in Johto the class table cannot reach it -- the
  -- LEDGE classes sit on the turf ABOVE the drop and the lip's own cell is
  -- plain $07 -- so it took a tile pin or it stood as a wall.  Kanto draws
  -- the lip as a course of cobbles: $37 the run, $36 and $34 its end caps,
  -- $27 and $24 the same course turned to face left and right, $0D the
  -- inside corner.  Every block that carries a ledge class is bounded by
  -- exactly these six and nothing else.
  ledge = { 0x0D, 0x24, 0x27, 0x34, 0x36, 0x37 },
  -- No `post` pin.  $4F was read as a wooden rail because its cells carry
  -- $70/$76/$7E, but CheckWarpCollision matches exactly those classes ($60,
  -- $68, high nybble $7): they are WARPS, so $4F is the entrance mat laid
  -- in front of a gate, and standing it up boxed off every doorway.
  -- the flowerbeds.  $03 is the one that matters -- the blossoms scattered
  -- through the turf of every Kanto town, drawn as a diagonal spray across
  -- a 2x2 block of walkable grass -- and it was missing, so every one of
  -- them was painted flat while Johto's ($03 there too) stood up and swayed.
  -- $04 is the denser bed of blocks $2F and $5C and was the only id here.
  flower = { 0x03, 0x04 },
  -- Kanto's two round tree drawings, both one cell tall: $2A/$2B/$3A/$3B the
  -- pale-crowned tree that borders the routes (48 cells) and $40/$41/$50/$51
  -- the dark leafy one the towns are hedged with (27).  Left to the volume
  -- path each row of them came out as one flat-topped plateau with the
  -- canopy printed on its lid; the cylinder archetype carves a voxel ball
  -- per cell from the crown's outline so they read as canopies.
  --
  -- The cut tree ($2D/$2E/$3D/$3E) and the boulder ($48/$49/$58/$59) need no
  -- pin: their cells carry classes $12 and $7B, which the collision map
  -- already rounds.
  cylinder = { 0x2A, 0x2B, 0x3A, 0x3B, 0x40, 0x41, 0x50, 0x51 },
  -- KANTO'S RAIL FENCE, the run that pens Pallet's yards and lines the
  -- ridge above Viridian: $0E over $55, one cell per bay, and drawn
  -- nowhere else in the set.  Its cells are plain $07, so a fence read as
  -- a solid 16px wall -- a row of barrels rather than a rail you could see
  -- the town through.
  --
  -- `post`, not `fence`: the fence class is a BOX at 10px, which turns a
  -- run into one continuous fence-textured kerb -- lower than a wall and
  -- still a wall.  A fence is mostly holes, and the post pool is the one
  -- that says so: it cuts the drawing per pixel and stands each CELL in
  -- its own depth band, so a run comes out as separate pickets with
  -- daylight between them.  Same class Johto's fence takes.
  post = { 0x0E, 0x55 },
  -- THE SIGNPOSTS: $46/$47 over $56/$57, a board on a stick, one cell,
  -- and again plain $07 so each stood as a cube.  `signpost` is the thin
  -- per-pixel plate the class exists for -- a sign is not furniture.
  signpost = { 0x46, 0x47, 0x56, 0x57 },
}

-- ---------------------------------------------------------------------------
-- KANTO'S BUILDINGS.
--
-- There was no `buildings` list for TilesetKanto at all -- Johto had ten
-- templates and Kanto none -- so every house, lab, Mart and Center west of
-- the Tohjo Falls fell to the volume path, and fell to it the same way
-- Johto's did before its list was written: Kanto's facade repeats its wall
-- course ($4B under $4B, $1A under $1A), the detector's trim-foot rule
-- reads a repeat, a repeat never roofs, and a six-tile-row drawing came out
-- as a 16px flat-lidded box with the roof printed on its lid.
--
-- Kanto's catalogue is drawn to the same three courses Johto's is -- a
-- ridge cap, a field, a fascia -- so the band table is Johto's unchanged
-- (2 back, 4 front, the middle cycling), and the templates differ only in
-- their tile grids and in how deep the roof band runs.
profile.buildings.TilesetKanto = {
  -- PEWTER MUSEUM, the biggest drawing in Kanto: 8 cells wide and 6 tall,
  -- and the gym's tiled pitch run a whole extra course deeper -- rows 0-6
  -- are roof (56px) over five rows of facade.  It has to come first: every
  -- narrower tiled template below is a sub-rectangle of its roof field in
  -- everything but the verge, and placement is first-claim-wins.
  {
    id = "kanto_museum",
    tiles = {
      { 0x05, 0x06, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x08, 0x09 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x28, 0x29 },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x0A, 0x32, 0x0A, 0x0A, 0x0A, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 56, roofBack = 2, roofFront = 4, roofCycle = { 2, 51 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- CERULEAN GYM: the tiled pitch again, 8 cells wide over four tall, with
  -- the twin sign panels ($2F/$3F between $22) across its lintel.
  {
    id = "kanto_gym_wide",
    tiles = {
      { 0x05, 0x06, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x08, 0x09 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0A, 0x0A, 0x22, 0x2F, 0x3F, 0x22, 0x22, 0x2F, 0x3F, 0x22, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x0F, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x1F },
      { 0x0F, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0B, 0x0C, 0x0A, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- ------------------------------------------------------------------
  -- THE SLATE OFFICE BLOCKS -- Vermilion, Saffron and Celadon are built
  -- almost entirely out of these, and not one of them had a template, so
  -- three whole cities came out as flat-lidded boxes.  All share the lab's
  -- cap ($4C/$4E/$4D over two courses of $5A/$5E over a $5C/$5F/$5D
  -- fascia) and differ only in footprint and in which window course
  -- ($0A/$32) and door ($0B/$0C over $1B/$1C) fill the facade.
  --
  -- Ordered tallest and widest first throughout: placement is
  -- first-claim-wins and every smaller block here is a sub-rectangle of a
  -- larger one's facade.
  --
  -- SILPH CO, eight cells wide and twelve tall, the tallest building in
  -- Kanto and twenty rows of repeating storey -- the volume path's
  -- trim-foot rule at its worst.
  {
    id = "kanto_silph",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x32, 0x4B, 0x4B, 0x32, 0x0A, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x0B, 0x0C, 0x0A, 0x0A, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- CELADON DEPARTMENT STORE: six cells wide, eight tall, MART ($44/$45
  -- over $4A) beside the door.
  {
    id = "kanto_dept_store",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x32, 0x4B, 0x4B, 0x32, 0x0A, 0x0A, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x0B, 0x0C, 0x0A, 0x0A, 0x44, 0x45, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x4A, 0x4A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the six-cell block six storeys tall: Celadon's Game Corner and the
  -- mansions that repeat its drawing.
  {
    id = "kanto_office_6x6",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x32, 0x4B, 0x4B, 0x32, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x0B, 0x0C, 0x0A, 0x0A, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the eight-cell hall, two storeys, its door off centre to the east
  {
    id = "kanto_office_8x4",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x0A, 0x32, 0x0A, 0x0A, 0x32, 0x4B, 0x4B, 0x32, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x0B, 0x0C, 0x0A, 0x0A, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the four-cell block, six storeys: Saffron's and Celadon's back lots
  {
    id = "kanto_office_4x6",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- and the four-cell block four storeys tall, with and without a door:
  -- the single commonest drawing in Kanto's cities
  {
    id = "kanto_office_4x4_door",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x0B, 0x0C, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  {
    id = "kanto_office_4x4",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- OAK'S LAB, and the same drawing wherever Kanto repeats it: 6 cells
  -- wide, 4 tall, with a 32px roof band ($4C/$4E/$4D cap, two courses of
  -- $5A/$5E field, a $5C/$5F/$5D fascia) over a two-cell brick facade.
  -- Listed first because it is the largest: placement is first-claim-wins
  -- and the smaller house below shares its wall tiles.
  {
    id = "kanto_lab",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x32, 0x4B, 0x4B, 0x32, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x0B, 0x0C, 0x0A, 0x0A, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- THE CIVIC BLOCK: the Center and the Mart, which share Oak's slate roof
  -- and differ from him only in where the door sits and how the brick runs
  -- under it.  Same 6x4 footprint, same 32px band.
  {
    id = "kanto_civic",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x0B, 0x0C, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the same slate block with no door at all: Pewter's civic hall and the
  -- warehouses that repeat it.  Its window course is the lab's, so it
  -- differs from the two above in the facade only.
  {
    id = "kanto_civic_blank",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x0A, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- THE GYM.  Also 6x4, but its roof is the tiled pitch the houses wear
  -- rather than the civic slate, run two courses deeper ($53 over $12 over
  -- $12 over $17) with the $38/$19 verge down both sides.
  {
    id = "kanto_gym",
    tiles = {
      { 0x05, 0x06, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x53, 0x08, 0x09 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0A, 0x0A, 0x22, 0x2F, 0x3F, 0x22, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x0F, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x1F },
      { 0x0F, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0B, 0x0C, 0x0A, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the tiled pitch on a FOUR-cell plot -- Cerulean's bike shop and the
  -- trade house, four cells square with a window course over the door.
  -- Two of them, one with a shutter ($32) where the other has plain wall.
  {
    id = "kanto_gym_small",
    tiles = {
      { 0x05, 0x06, 0x53, 0x53, 0x53, 0x53, 0x08, 0x09 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0A, 0x0A, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x0F, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x1F },
      { 0x0F, 0x0A, 0x0A, 0x0A, 0x0B, 0x0C, 0x0A, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  {
    id = "kanto_gym_small_shutter",
    tiles = {
      { 0x05, 0x06, 0x53, 0x53, 0x53, 0x53, 0x08, 0x09 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x38, 0x12, 0x12, 0x12, 0x12, 0x38, 0x19 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0A, 0x0A, 0x32, 0x0A, 0x28, 0x29 },
      { 0x0F, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x1F },
      { 0x0F, 0x0A, 0x0A, 0x0A, 0x0B, 0x0C, 0x32, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- THE MART: the same slate roof again, but only 4 cells wide over four
  -- tall, with the MART board ($44/$45 over $4A) beside its door.  It is
  -- listed above the houses because it is four rows deep and they are two
  -- and three -- a shorter template placed first would claim its facade
  -- and leave the roof to the volume path, which is what the first draft
  -- of this list did.
  {
    id = "kanto_mart",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x0A, 0x0A, 0x0A, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x0B, 0x0C, 0x44, 0x45, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x4A, 0x4A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- THE POKEMON CENTER, the Mart's twin down to the tile with the POKe
  -- board ($42/$43) hung where the Mart's ($44/$45) is.  Every Center in
  -- Kanto is this drawing, so its absence was one missing building per
  -- town -- and always the one the player walks up to first.
  {
    id = "kanto_center",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
      { 0x0F, 0x0A, 0x32, 0x0A, 0x0A, 0x0A, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x0B, 0x0C, 0x42, 0x43, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x4A, 0x4A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- THE KANTO HOUSE: 4 cells wide, 3 tall.  The roof runs four tile rows
  -- deep here rather than the lab's four-over-a-taller-wall -- $05..$09
  -- and $15..$19 the pitched field, $25/$26/$28/$29 the eave corners,
  -- $5C/$5D closing the fascia -- over a single-cell facade with the
  -- door ($0B/$0C over $1B/$1C, the cell the game marks $71) in it.
  {
    id = "kanto_house",
    tiles = {
      { 0x05, 0x06, 0x07, 0x07, 0x07, 0x07, 0x08, 0x09 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x32, 0x22, 0x32, 0x32, 0x28, 0x29 },
      { 0x5C, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x5D },
      { 0x0F, 0x22, 0x0B, 0x0C, 0x0A, 0x0A, 0x22, 0x1F },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- THE ROW HOUSES, the cottage stretched along its ridge: the same two
  -- roof rows over a single facade course, but six and eight cells wide
  -- with the shuttered bay ($23/$32/$0A/$23) repeated between the ends.
  -- These are the ordinary houses of Cerulean, Vermilion, Saffron and
  -- Celadon -- the bulk of every Kanto town -- and only the four-cell
  -- cottage below had a template, so the wide ones stood as boxes.
  -- Widest first, and all three ahead of the cottage.
  {
    id = "kanto_row_8x2_door",
    tiles = {
      { 0x05, 0x06, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x08, 0x09 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0B, 0x0C, 0x23, 0x32, 0x0A, 0x23, 0x23, 0x32, 0x0A, 0x23, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  {
    id = "kanto_row_6x2_door",
    tiles = {
      { 0x05, 0x06, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x08, 0x09 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0B, 0x0C, 0x23, 0x32, 0x0A, 0x23, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  {
    id = "kanto_row_6x2_window",
    tiles = {
      { 0x05, 0x06, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x08, 0x09 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0A, 0x22, 0x23, 0x32, 0x0A, 0x23, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- THE COTTAGE: the same drawing with the upper wall course cut away, 4
  -- cells wide and 2 tall, which is the ordinary house of every Kanto
  -- town.  Two of them, differing only in whether this face carries the
  -- door ($0B/$0C) or a window ($0A/$22) -- and they must come after the
  -- three-cell house above, because their two roof rows are its two roof
  -- rows and placement is first-claim-wins.
  {
    id = "kanto_cottage_door",
    tiles = {
      { 0x05, 0x06, 0x07, 0x07, 0x07, 0x07, 0x08, 0x09 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0B, 0x0C, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x1D, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  {
    id = "kanto_cottage_window",
    tiles = {
      { 0x05, 0x06, 0x07, 0x07, 0x07, 0x07, 0x08, 0x09 },
      { 0x15, 0x16, 0x17, 0x17, 0x17, 0x17, 0x18, 0x19 },
      { 0x25, 0x26, 0x0A, 0x22, 0x0A, 0x0A, 0x28, 0x29 },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 16, roofBack = 2, roofFront = 4, roofCycle = { 2, 11 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- ------------------------------------------------------------------
  -- THE CLIPPED ONES, and they have to come LAST.  Both grids below are
  -- sub-rectangles of a whole block above, so first-claim-wins is the only
  -- thing keeping them from stealing ordinary placements: every full
  -- drawing must have had its chance before these two are offered.
  --
  -- THE KANTO RADIO TOWER at Lavender: six cells wide, six storeys, and
  -- its cap is off the north edge of the map, so the roof is supplied by
  -- `topRows` instead of being read off the drawing.
  {
    id = "kanto_tower_clipped",
    topRows = {
      { 0x4C, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4E, 0x4D },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5A, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5E, 0x5A },
      { 0x5C, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5D },
    },
    tiles = {
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x0A, 0x32, 0x32, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x32, 0x0A, 0x32, 0x32, 0x0A, 0x0A, 0x32, 0x0A, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x32, 0x0A, 0x0A, 0x32, 0x4B, 0x4B, 0x32, 0x32, 0x0A, 0x32, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x0F, 0x4B, 0x4B, 0x4B, 0x0B, 0x0C, 0x0A, 0x0A, 0x4B, 0x4B, 0x4B, 0x1F },
      { 0x1D, 0x1A, 0x1A, 0x1A, 0x1B, 0x1C, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x3C },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
  -- the Safari Zone's west block at Fuchsia, whose eastern half is off the
  -- map: only the two western cells of a four-cell office survive, so the
  -- silhouette is sealed on the east and nothing is inferred beyond it.
  {
    id = "kanto_office_2x4_clipped_e",
    tiles = {
      { 0x4C, 0x4E, 0x4E, 0x4E },
      { 0x5A, 0x5E, 0x5E, 0x5E },
      { 0x5A, 0x5E, 0x5E, 0x5E },
      { 0x5C, 0x5F, 0x5F, 0x5F },
      { 0x0F, 0x32, 0x0A, 0x0A },
      { 0x0F, 0x4B, 0x4B, 0x4B },
      { 0x0F, 0x4B, 0x4B, 0x4B },
      { 0x1D, 0x1A, 0x1A, 0x1A },
    },
    roofRows = 32, roofBack = 2, roofFront = 4, roofCycle = { 2, 27 },
    slab = 4, frontEave = 4, ledge = nil,
  },
}

-- ---------------------------------------------------------------------------
-- THE INTERIORS.
--
-- Nothing indoors in Generation 2 had a pin of any kind, so every room in
-- the game came out of `forMap`'s fallback as a field of identical 16px
-- cubes: the Centers' healing machine, their PC, the Marts' stock shelves,
-- the tables you sit at and the stools you sit on were all the same grey
-- box in the same place, each wearing its own drawing in relief.
--
-- Most of it is fixed one storey up, in the `collision` table: the ROM
-- names a bookshelf, a PC, a radio, a Mart shelf, a TV and a burner
-- outright, and eight rows there reach all twenty-odd indoor tilesets at
-- once.  What is left over is the furniture the ROM does NOT name -- it is
-- all plain class $07, the same class as the wall behind it -- and that
-- takes a tile pin per tileset, which is what follows.
--
-- Two shapes carry most of the load:
--
--   `bookcase`  for a drawing that is TALL rather than deep -- a machine
--               or a shelf standing against a wall, drawn across two cell
--               rows because that is how you draw height on a flat map.
--               Structures collapses its drawn ranks onto ONE cell of
--               plot at full 32px height, which is the difference between
--               a healing machine and two crates stacked front to back.
--   `table` /   for furniture drawn from ABOVE at its real footprint --
--   `stool`     a 12px table you can see the top of, an 8px seat a
--               character stands at the right height on.
--
-- ---------------------------------------------------------------------------
-- TilesetPokecenter -- every Pokemon Center in Johto and Kanto.
profile.tilesets.TilesetPokecenter = {
  -- THE HEALING MACHINE, the drawing this whole pass was reported for.
  -- It is 2x2 cells in the room's north-west corner and every one of the
  -- four is class $07, indistinguishable from the wall it stands against,
  -- so it stood as four cubes with the console printed on their faces.
  -- The drawing is two cells TALL and one deep -- the upper rank is the
  -- machine's height, not a second machine behind the first -- which is
  -- the `bookcase` archetype exactly.
  --
  -- The tiles are the whole 2x2 as Cherrygrove draws it and as every
  -- other Center repeats it: $1C-$1F and $2C-$2F the head with its two
  -- green monitors, $3C-$3F and $4C-$4F the console body and the bay
  -- the balls sit in.
  bookcase = { 0x1C, 0x1D, 0x1E, 0x1F, 0x2C, 0x2D, 0x2E, 0x2F,
               0x3C, 0x3D, 0x3E, 0x3F, 0x4C, 0x4D, 0x4E, 0x4F,
               -- and the cabinet standing beside it ($04/$05 over
               -- $14/$15, on $0A/$0B over $1A/$1B), the same two-rank
               -- drawing one cell wide
               0x04, 0x05, 0x0A, 0x0B, 0x14, 0x15, 0x1A, 0x1B,
               -- THE PC on the east wall.  One cell wide and TWO cells
               -- tall -- $20/$21 the screen, $30/$31 the body twice over,
               -- $40/$41 the base -- and nothing named it, so the upper
               -- cell stood as a 16px wall panel and the lower one as the
               -- $93 `console` standee: the machine came out cut in half
               -- with a slab of wall balanced on it.  Same two-rank
               -- drawing as the healing machine, so the same class.
               0x20, 0x21, 0x30, 0x31, 0x40, 0x41,
               -- THE DRINKS COOLER at the counter's east end, drawn from
               -- the wall down onto the counter top ($0F the wall rank,
               -- $03/$25 the middle, $13/$35 over $46/$47 the body).  All
               -- three of its cells are plain $07, so it was three 16px
               -- wall panels in a row running out into the room -- the
               -- column that stood between the camera and the nurse.
               0x0F, 0x03, 0x25, 0x13, 0x35, 0x46, 0x47 },
  -- THE FLOOR, pinned.  The strip the nurse stands on behind the counter
  -- is blocked ($07) simply because the counter is in the way, but it is
  -- DRAWN as the same floor as the lobby ($01 over $11).  Unpinned it fell
  -- to rule 4's wall fallback and put a 16px slab either side of her.
  ground = { 0x01, 0x11 },
  -- The nurse's counter.  Its run carries class $90 and the collision
  -- table already reaches that, but the cell holding the ball tray
  -- ($0C, which is the ball itself) is plain $07 and would have stayed a
  -- wall stub in the middle of the counter.  The apron ($24) and the top
  -- band ($34) are pinned with it so the whole run is one 8px band
  -- whether or not a given cell got the class.
  counter = { 0x0C, 0x24, 0x34 },
  -- the lounge tables, four cells of them along the east wall
  table = { 0x48, 0x49, 0x58, 0x59 },
  heights = { table = 6 },
}

-- ---------------------------------------------------------------------------
-- TilesetMart -- the Poke Marts.
--
-- The stock shelves are the one drawing here the class table does not
-- finish.  Each is two cell rows: the lower carries $96 (the ROM's own
-- MerchandiseShelfScript class) and is now a 32px bookcase, but the upper
-- rank is plain $07 and stayed a 16px wall panel standing behind it -- a
-- shelf with a shelf-shaped step parked at its back.  Pinning the upper
-- rank into the same class folds both onto one cell of plot, which is
-- what the drawing means.
profile.tilesets.TilesetMart = {
  bookcase = { 0x0C, 0x0D, 0x40, 0x41, 0x42, 0x2B, 0x45, 0x50, 0x51,
               0x52, 0x56, 0x57, 0x26, 0x27, 0x36, 0x37, 0x28, 0x29,
               0x38, 0x39 },
}

-- ---------------------------------------------------------------------------
-- TilesetHouse -- the ordinary Johto town home (the Olivine fisherman's,
-- Tim's, and the two dozen others cut from the same room).  Nothing in it
-- was pinned, so every stick of furniture fell to the wall fallback its
-- blocked collision class hands out and stood a full 16px course.
profile.tilesets.TilesetHouse = {
  -- THE DINING TABLE, four cells of it.  6px is the table family's own
  -- height (see PLAYERS_HOUSE below for why the number matters as much as
  -- the size); at 16 it stood shoulder-high on the man sitting at it.
  table = { 0x05, 0x15, 0x26, 0x27, 0x29, 0x2F, 0x36, 0x39,
            0x3A, 0x3B, 0x3C },
  heights = { table = 6 },
  -- THE TELEVISION, and the set along the same wall.  Each is drawn three
  -- tile rows tall and the top row lands in the CELL ABOVE -- the north
  -- wall band -- so the screen stood inside the wall a cell behind its own
  -- base.  `console` is what the lower cell already resolves to through
  -- its collision class, so naming the stray row the same puts the whole
  -- set in one standee.
  console = { 0x06, 0x07, 0x0C, 0x0D },
  -- THE POTTED TREES in the two south corners: a round drawing stacked two
  -- cells high on one cell of plot, which is what `planter` is for.  BOTH
  -- cells take the pin -- the crown anchors the carve and the pot cell is
  -- the plot it stands in, and with only one of them pinned Structures
  -- refuses the hull and the two halves came out as separate objects, the
  -- bush sitting behind its own pot instead of on it.
  planter = { 0x08, 0x09, 0x0A, 0x0B, 0x18, 0x19, 0x1A, 0x1B },
  -- ...and not as a SPRAY.  The class caps the crown to a five-voxel slab
  -- because a pot plant's leaves are a flat fan; this one is a little tree
  -- and reads as a ball, so every drawn row turns the full 16px.
  planter_spray = false,
  -- $3B/$3C are the table's south rim AND the bookcase's base course, and
  -- a bookcase is 32px of shelving.  What is drawn one row above tells
  -- them apart: the bookcase's own ranks, or more table.
  when_above = {
    [0x3B] = { { above = { 0x0E, 0x0F }, class = "bookcase" } },
    [0x3C] = { { above = { 0x0E, 0x0F }, class = "bookcase" } },
  },
}

-- ---------------------------------------------------------------------------
-- TilesetPlayersHouse -- the ground floor of the player's house, and the
-- ordinary Johto home that shares its drawings.
profile.tilesets.TilesetPlayersHouse = {
  -- THE STOOLS around the dining table, four of them, drawn from above as
  -- a round cushion.  Their cells are class $00 -- the game lets you walk
  -- onto a stool -- so they were flat floor rather than boxes, which is
  -- the opposite failure and just as wrong: a character crossing the
  -- kitchen walked through the seats. 8px is the seat, and a character
  -- standing on one stands on it.
  stool = { 0x02, 0x03, 0x12, 0x13 },
  -- the dining table between them, and the kitchen counter along the
  -- north wall, which are the same drawing in the same ids -- including
  -- the one-cell-wide run of it that goes north-south beside the stairs,
  -- which is $25 and $35 side by side rather than stacked
  table = { 0x15, 0x22, 0x23, 0x24, 0x25, 0x32, 0x33, 0x34, 0x35 },
  -- the sink unit under the window and the cabinet beside the stairs.
  -- Both are drawn two cell rows tall against the north wall, so both are
  -- height rather than depth: one cell of plot at full height.
  bookcase = { 0x18, 0x19, 0x43, 0x45, 0x50, 0x51, 0x52, 0x53,
               0x0A, 0x0B, 0x1A, 0x1B, 0x2A, 0x2B },
  -- THE TABLE FAMILY'S OWN HEIGHT.  The global `table` is 12 and the Gen 1
  -- tilesets all override it to 6, which is what their crafted models
  -- measure -- and 6 is not just a size here, it is what makes a tabletop
  -- READ.  A pinned upright box tops itself with the drawn row
  -- `front - floor(h/8)` (ChunkMesher), so at 12 a table drawn TWO cells
  -- deep wears its north row across the whole lid: the drawn south rim
  -- never lands, the surface comes out as one smeared band, and the thing
  -- stands three quarters as tall as the player.  At 6 the divisor is zero,
  -- every cell wears its own drawn row, and the rim, the highlight course
  -- and the field fall where the artist put them.
  heights = { table = 6, stool = 5 },
}

-- ---------------------------------------------------------------------------
-- TilesetPlayersRoom -- the player's bedroom, and the one room every save
-- file starts in.
-- Three machines stand in a row along one desk here -- the computer, the
-- stereo beside it and the games console under the television -- and a
-- standee pool clusters whatever touches it. Put all three in `console`
-- and they merge into a single drawing, whereupon that class's one-object
-- contract keeps the largest connected shape and throws the rest away.
-- Each takes its own pool so each is measured, and stands, alone.
profile.tilesets.TilesetPlayersRoom = {
  -- the bed, drawn from above like every bed in the game
  bed = { 0x10, 0x11, 0x12, 0x20, 0x21, 0x22 },
  -- the computer: monitor over keyboard, two cell rows of drawing on one
  -- cell of desk. A standee and not a box, because a box lids itself with
  -- its own north row -- which prints the screen a second time, lying
  -- flat on the machine's top, and hands the cell above it to the wall.
  console = { 0x0B, 0x0C, 0x1B, 0x1C, 0x2B, 0x2C },
  -- the stereo, and the lamp arm reaching over it: mostly silhouette, so
  -- the thin pool
  prop = { 0x42, 0x43, 0x52, 0x53 },
  -- the television: $3B/$3C for the set's upper case, $4B/$4C for the
  -- screen, $5B/$5C for the stand it rests on.  The top row is drawn in
  -- the cell ABOVE, which is wall -- so the screen stood inside the wall
  -- band while only the stand came forward.  Naming those two tiles takes
  -- them out of the wall and into the same standee as the rest of the
  -- set; the $02 planks either side of them stay wall, which is what they
  -- are.  All four tiles of the lower cell are named too: a tile left out
  -- of a pin does not become scenery, it falls through to the cell's
  -- collision class -- $97, the television -- and builds a SECOND standee
  -- from the leftovers, standing in the same place as the first.
  billboard = { 0x3B, 0x3C, 0x4B, 0x4C, 0x5B, 0x5C },
}

-- ---------------------------------------------------------------------------
-- TilesetLab -- Elm's lab, Oak's, and the Cinnabar and Union Cave labs.
profile.tilesets.TilesetLab = {
  -- the long benches down the middle of the floor: one cell row with
  -- their own shadow drawn on the walkable cell south of them, so they
  -- are furniture standing in the room rather than anything against a
  -- wall.  6px is the table family's own height (see PLAYERS_HOUSE): at
  -- the global 12 the bench stood three quarters as tall as the player
  -- and lost its drawn rim off the lid.
  table = { 0x05, 0x06, 0x07, 0x15, 0x16, 0x17, 0x0E, 0x0F, 0x1E, 0x1F },
  -- Elm's machine bank along the north and west walls -- the terminals,
  -- the incubator and the tape reels.  `console` rather than `desk` for
  -- the reason the PC classes take it: the upright fold repeats a box's
  -- north row across its lid, so a terminal wore its own screen twice.
  console = { 0x0A, 0x0B, 0x0C, 0x0D, 0x1A, 0x1B, 0x1C, 0x1D,
              0x22, 0x23, 0x32, 0x33,
              0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x49,
              0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59 },
  heights = { table = 6 },
}

-- ---------------------------------------------------------------------------
-- TilesetTower -- Sprout Tower, the Burned Tower, the Tin Tower and the
-- Ecruteak gym, which is built in the same timber.
profile.tilesets.TilesetTower = {
  -- $01 is not a wall, it is NOTHING: the black surround these maps are
  -- padded out to a full 20 cells with, two columns of it down each side
  -- of every floor.  Its cells are class $07 like everything solid, so it
  -- came out as a 16px black kerb ringing the tower -- a room inside a
  -- box.  Flat, and the tower stands in the dark it is drawn in.
  void = { 0x01 },
  -- $02 is the plain planking.  $0A/$0B/$1A/$1B are the DARK bays laid
  -- around the spine on the upper floors -- close-set joists seen from
  -- above, a floor pattern and nothing more.  Their cells are blocked
  -- ($07) like everything else here, so unpinned they fell to the wall
  -- fallback and stood as four 16px slabs boxing the beam in.
  ground = { 0x02, 0x0A, 0x0B, 0x1A, 0x1B },
  -- the great square beam through the middle of every floor, two cells
  -- wide and three tall: the tower's spine, and the one thing here that
  -- genuinely runs past the ceiling.  32px, twice a wall, so it leaves
  -- the top of the frame instead of stopping at head height.
  cliff = { 0x2D, 0x2E, 0x2F, 0x3C, 0x3D, 0x3E, 0x3F,
            0x4D, 0x4E, 0x4F, 0x5D, 0x5E, 0x5F },
  -- The RAILING, in its two projections.  $11/$21 is the east-west run
  -- seen face on -- balusters with daylight between them -- and the post
  -- pool cuts that per pixel and stands each cell alone.  $41/$31 is the
  -- same railing seen END ON, one cell wide and repeated seamlessly down
  -- the whole run, with $40/$20 the corner cell where the two meet.  Read
  -- as columns flanking the beam they took the beam's 32px and were cut
  -- per cell like the face-on rows, so the north-south rail came out as a
  -- chain of separate slabs stepping away from the camera at twice the
  -- height of the rail it turns into.  `fence` is the continuous kerb the
  -- end-on view depicts, at the face-on run's own height.
  fence = { 0x41, 0x31, 0x40, 0x20 },
  post = { 0x11, 0x21 },
  -- ...and `rail_face` is what the end-on run is BUILT from: the panel
  -- stands 6px thick down the middle of its cells and wears the face-on
  -- drawing on both flanks, so walking beside it in first person shows a
  -- railing rather than the end grain of a plank.  See Structures'
  -- buildRails.
  rail_face = { 0x11, 0x21 },
  heights = { fence = 16 },
  -- the gilded Bellsprout statues flanking the stairs, drawn over one
  -- cell of plot and two cell rows: $4A/$4B over $5A/$5B for the head and
  -- body, $4C/$5C for the leaves it holds out, $36/$37 for the stone base
  -- under them.  Every tile of both cells, because a tile left out of a
  -- pin does not become scenery -- it falls through to the cell's
  -- collision class, $07, and stands as a plank slab through the middle
  -- of the statue.  `billboard` and not `bookcase`: the collapse a
  -- bookcase does is onto a BOX, and a box lids itself by repeating its
  -- north row, so each statue wore a second copy of its own face flat
  -- across the top of its head.
  billboard = { 0x4A, 0x4B, 0x5A, 0x5B, 0x4C, 0x5C, 0x36, 0x37,
                -- and the OTHER statue on the same atlas: the lidded urn on
                -- its pedestal that flanks the Burned Tower's and the Tin
                -- Tower's entrances (blocks $19/$1A and $21/$22, mirrored).
                -- It shares the Bellsprout's $36/$37 base and nothing else,
                -- so its own six tiles fell through to the cell's class,
                -- $07, and each urn stood as a pair of plain wall cubes --
                -- the "statue that isn't drawn like the other statues".
                0x22, 0x23, 0x32, 0x33, 0x12, 0x13 },
  -- The statue is gilded in the same GB shades the floor is planked in,
  -- and it fills its own cell edge to edge, so the rim vote read its body
  -- as background and drained it: what stood was the black outline alone,
  -- a charred shell with the gold surviving only where the flood could not
  -- reach.  There is no shade to name here -- `dark` is the floorboard
  -- around the head AND the gold's own shading, and draining it guts the
  -- body a second time (tried, and it does).  Nothing is background.
  prop_bg = { { tiles = { 0x4A, 0x4B, 0x5A, 0x5B, 0x4C, 0x5C, 0x36, 0x37,
                          0x22, 0x23, 0x32, 0x33, 0x12, 0x13 },
                shades = { "none" } } },
}

-- ---------------------------------------------------------------------------
-- TilesetEliteFourRoom -- despite the name, this is the JOHTO GYM set:
-- Violet, Azalea and Goldenrod are all built from it.
profile.tilesets.TilesetEliteFourRoom = {
  ground = { 0x01, 0x11 },
  -- the same black padding TilesetTower has, and the same failure: six
  -- columns of it down each side of a gym, every cell class $07, standing
  -- as a black wall around a room that already has walls.
  void = { 0x00 },
  -- the badge statues either side of the leader's mat -- the ones you
  -- read for the gym's inscription -- one cell of plot and two cell rows
  -- of drawing ($20/$21 over $30/$31, standing on $22/$23 over $32/$33).
  -- Cut per pixel rather than collapsed onto a box, which would lid each
  -- one with a repeat of its own inscribed face.
  billboard = { 0x20, 0x21, 0x22, 0x23, 0x30, 0x31, 0x32, 0x33 },
  -- and the same trap Sprout Tower's statues fell into: the statue fills
  -- its cells edge to edge, so the rim vote reads its own body as
  -- background, drains it, and leaves the black outline standing alone.
  prop_bg = { { tiles = { 0x20, 0x21, 0x22, 0x23, 0x30, 0x31, 0x32, 0x33 },
                shades = { "none" } } },
  -- the pedestals ranged along the walls, in their own pool so a statue
  -- standing next to one is still measured as a separate object
  prop = { 0x55, 0x56, 0x57, 0x58 },
}

-- ---------------------------------------------------------------------------
-- TilesetRuinsOfAlph -- the four Unown chambers.
profile.tilesets.TilesetRuinsOfAlph = {
  -- the stone floor
  ground = { 0x02, 0x03 },
  -- the carved pillars flanking the Unown wall: $0E/$0F over $1E/$1F for
  -- the capital, $2E/$2F over $3E/$3F for the shaft. A pillar is the one
  -- thing in a ruin that is unmistakably tall, and both cells of it were
  -- separate 16px cubes standing one behind the other, each capped with a
  -- repeat of the carving on its face.
  billboard = { 0x0E, 0x0F, 0x1E, 0x1F, 0x2E, 0x2F, 0x3E, 0x3F },
}

-- ---------------------------------------------------------------------------
-- TilesetForest -- Ilex Forest, and only Ilex Forest.
--
-- Its big trees are drawn as one 4x4-TILE mass ($0C-$0F over $1C-$1F over
-- $2C-$2F over $3C-$3F, blocks $00 and $05), which is TWO CELLS square, and
-- every one of those cells carries class $07.  The volume path read that as
-- what it looks like from above -- a flat-topped green plateau with the
-- canopy pattern printed on its lid -- which is the failure Viridian
-- Forest's trees have upstairs, and it takes the same answer: `canopy` pins
-- the drawing's top-left tile as the group anchor and carves the whole 2x2
-- as ONE 32px voxel hull, with every other tile of the mass left `cylinder`
-- so the group build can verify and claim its cells (and so a drawing cut
-- by a map edge degrades to per-cell hulls rather than back to a box).
--
-- The small round tree ($26/$27/$36/$37) and the berry tree ($28/$38/$39/$3A)
-- need no pin: their cells carry classes $15 and $12, which the collision
-- map already rounds.  Neither is the cut tree -- Ilex's is a map OBJECT,
-- not a tile -- so nothing here touches one.
profile.tilesets.TilesetForest = {
  ground = { 0x05 },
  water = { 0x14 },
  flower = { 0x03 },
  canopy = { 0x0C },
  cylinder = { 0x0D, 0x0E, 0x0F, 0x1C, 0x1D, 0x1E, 0x1F,
               0x2C, 0x2D, 0x2E, 0x2F, 0x3C, 0x3D, 0x3E, 0x3F },
}

-- ---------------------------------------------------------------------------
-- TilesetPark -- the National Park, the Bug-Catching Contest's arena.
--
-- Two things here are grass and only one of them was being drawn as grass.
-- Block $03 is the ordinary tall grass, class $18, which the collision map
-- already stands up as tufts.  Block $13 -- the long clumped grass the
-- contest is fought in, and the one drawing a player spends the whole event
-- looking at -- carries class $14 instead, which is not one of
-- CheckGrassCollision's ten and is plain LAND, so the cell rules painted it
-- flat: a contest in a meadow with no meadow in it.  A tile pin reaches
-- what the class cannot.
--
-- The big trees are the same 4x4-tile mass FOREST draws (blocks $00 and $06
-- here) and take the same canopy treatment.
profile.tilesets.TilesetPark = {
  ground = { 0x01 },
  -- the ornamental pond.  $14 is its surface and $15 the pale shallow rim,
  -- and neither is drawn anywhere else in the set -- but only the four cells
  -- of open water in the middle carry a WATER class ($21); every rim cell is
  -- plain $07, because the pond cannot be surfed.  So the cell rules read
  -- the whole shoreline as wall and stood the rim up as a ring of blue
  -- crates around a flat pool.  Same fix Johto's $58 shore takes.
  water = { 0x14, 0x15 },
  -- the contest's long grass ($3A/$3B over $4A/$4B, block $13 alone)
  grass = { 0x3A, 0x3B, 0x4A, 0x4B },
  -- No `post` pin: $4F's cells (blocks $0A/$0B) carry $70/$7E, which
  -- CheckWarpCollision matches, so it is the park gate's entrance mat.
  canopy = { 0x0C },
  cylinder = { 0x0D, 0x0E, 0x0F, 0x1C, 0x1D, 0x1E, 0x1F,
               0x2C, 0x2D, 0x2E, 0x2F, 0x3C, 0x3D, 0x3E, 0x3F },
}

-- ---------------------------------------------------------------------------
-- TilesetCave / TilesetDarkCave -- byte for byte the same blockset and the
-- same 96 tiles (Union Cave, Mt. Mortar, Dark Cave, Slowpoke Well: 32 maps
-- between them), so one description serves both.
--
-- The rocks are drawn ROUND -- one boulder per cell, $0C/$0D over $1C/$1D,
-- fifteen blocks of them and drawn nowhere else -- and their cells are plain
-- $07, so the volume path boxed every one and a cavern floor came out
-- cobbled with 16px crates.
--
-- Everything else solid is ONE rock family.  Counted over all 52 maps the
-- two sets serve, the blocked tiles are exactly $05 $07 $0A $0B $10 $15
-- $17 $1A $1B $25 $26 $27 -- $26 alone is 19,000 cells -- and not one of
-- them was named, so every one fell through to rule 4's 16px `wall`.  That
-- is the Burned Tower basement's whole complaint: a cavern rendered as a
-- floor plan of knee-high kerbs you see straight over, with the volume
-- path picking a different height for each run it decided was an object.
-- Pinned they skip detection, and `cliff` is the same upright fold two
-- courses tall -- which is what the inside of a mountain wants.
--
-- The rest is walkable: $01/$16 are the two floor shades and $24 the band
-- drawn along a raised floor's edge (also the doorstep under an exit,
-- $B2), $36/$37 the staircase, $20-$23/$28-$2B/$30-$33/$38-$3B the ladder
-- ($72), and $0E/$0F/$1E/$1F the cave mouth ($7B).  $40 is the WATERFALL
-- sheet (collision $33) and is shaped by class, not by tile id -- see
-- profile.collision.
local cave = {
  -- $01 is the LOW floor and $16/$24 the HIGH one.  Gen 2 records no
  -- elevation at all -- both are collision $00 -- so the only statement
  -- that a cave has two levels is the change of floor shade, and the rock
  -- band drawn between them is the same $26 family as any other wall.
  -- Read as one floor the Burned Tower's basement came out as a maze of
  -- kerbs on a billiard table, with the plateau the three beasts stand on
  -- flush with the pit you fall into to reach it.  `terrace` is the class
  -- for exactly this (see TileShape): raised GROUND, drawn on the top face
  -- of its box, at the height of the cliff that holds it up.
  ground = { 0x01 },
  terrace = { 0x16, 0x24 },
  water = { 0x14 },
  cylinder = { 0x0C, 0x0D, 0x1C, 0x1D },
  cliff = { 0x05, 0x07, 0x0A, 0x0B, 0x10, 0x15, 0x17,
            0x1A, 0x1B, 0x25, 0x26, 0x27 },
  -- $40 is the FALL itself: a band of it laid across the river, eight
  -- blocks wide, four cells deep at Mt. Mortar and the same shape at
  -- Tohjo Falls, Whirl Island B2F and Silver Cave.  Its cells are
  -- COLL_WATERFALL and its neighbours COLL_WATER, and a class pin cannot
  -- reach it -- the cell is water as far as the water pass is concerned,
  -- so the river came out one flat sheet with a texture change across the
  -- middle.  A TILE pin outranks every cell rule, and `waterfall` stands
  -- the falling water on its face the way it falls -- at the height the
  -- map DRAWS it, with the river it pours out of raised to its crest
  -- (Structures.buildFalls).  Pinned `cliff` at a flat 32px instead, the
  -- fall was a kerb and the upper river sat at the bottom of it.
  waterfall = { 0x40 },
  -- One course, wall and raised floor alike.  The rock band drawn between
  -- two cave levels is the same $26 family as the chamber walls, so the
  -- face that holds a terrace up can only ever be as tall as a `cliff` --
  -- and the flight that climbs it ($36) is a single block.  At 32 the deck
  -- stood a block clear of the top step.
  heights = { cliff = 16, terrace = 16 },
  -- ...but a rock lip you can HOP down is a ledge like any other, and the
  -- caves draw theirs out of the same $26 band as the walls, so the lip
  -- has to be found from the neighbouring $A1/$A3/$A5 cell.  See
  -- TileShape's HOP_LIP.
  hop_lips = true,
  -- The staircase is set INTO the floor it serves and nothing in its
  -- drawing says which of the two that is, so on the raised floor it came
  -- out as a pit through the deck (Mt. Mortar's sand shelf, the flight up
  -- to the Burned Tower's plateau).  What is drawn north of it does say:
  -- a flight is always entered from its own level, and the run above the
  -- top step is either raised floor or more of the same flight.
  when_above = {
    [0x36] = { { above = { 0x16, 0x24, 0x36 }, class = "terrace" } },
    [0x37] = { { above = { 0x16, 0x24, 0x37 }, class = "terrace" } },
  },
}
profile.tilesets.TilesetCave = cave
profile.tilesets.TilesetDarkCave = cave

-- ---------------------------------------------------------------------------
-- TilesetLighthouse -- the Olivine Lighthouse (11 floors).
--
-- Standard interior: collision class $07 = wall (16px box), $00 = floor.
-- The staircase tiles ($08/$09/$18/$19, class $00, walkable) would be flat
-- floor without pins.  Mark them as stools (8px) so they read as steps
-- instead of a flat ramp.  Class $90 counter, $91 bookshelf, $96 shelf use
-- the existing collision-class pins already wired globally.
profile.tilesets.TilesetLighthouse = {
  -- staircase cells rendered as a low step rather than flat floor
  stool = { 0x08, 0x09, 0x18, 0x19 },
  -- the crate/box props common to Lighthouse interiors
  table = { 0x20, 0x21, 0x22, 0x23, 0x30, 0x31, 0x32, 0x33 },
}

return profile
