-- Voxel world mode: THE GEN 3 SHAPE PROFILE.
--
-- Hand-authored by this mod and read only from here.  Nothing below is
-- extracted, derived or copied from the ROM; nothing here reaches gameplay,
-- collision or scripts.  An entry can only ever change how a cell LOOKS.
--
-- This is the Gen 3 counterpart of `collision` in data/voxel_heights.lua, and
-- it is deliberately a SEPARATE table rather than more rows in that one.  Gen
-- 2 collision classes and Gen 3 behaviour bytes are two unrelated numberings
-- that overlap end to end -- $02 is tall grass here and a wall class there --
-- so merging them would not make a bigger table, it would make a wrong one.
-- And it would be wrong SILENTLY, which is the failure mode this mod has paid
-- for more than once.
--
-- ---------------------------------------------------------------------------
-- WHAT A BEHAVIOUR BYTE IS
-- ---------------------------------------------------------------------------
--
-- Every Gen 3 metatile carries a 16-bit attributes word.  Its low byte is the
-- BEHAVIOUR: one of 240 named values saying what kind of surface this is.
-- Bits 12-15 are the LAYER TYPE.  Bits 8-11 are unused in Emerald -- there is
-- no terrain-type and no encounter-type field here, whatever FireRed does.
--
-- The behaviour says what a cell IS, not whether you can walk on it.
-- Passability is the map CELL's business (the blockdata word's collision
-- bits), because in Gen 3 the same metatile is a wall in one place and a
-- doorway in another -- a house front and its door are one tile.  So
-- MB_NORMAL tells you almost nothing on its own, and most of the world is
-- MB_NORMAL: the rows below are the cells that DO announce themselves, and
-- Gen3.classAt handles the rest from the collision bit and the layer type.
--
-- Every behaviour Emerald actually defines has a row.  The 75 MB_UNUSED_*
-- values do not, and that is the whole of what is missing.
--
-- Classes are this mod's own vocabulary (lib/TileShape.lua, FALLBACK_HEIGHTS)
-- with three added for Gen 3:
--
--   bridge   a DECK: flat, thin, standing at its cell's own elevation with a
--            fascia down its open sides.
--   log      a floating raft, riding barely clear of the water.
--   slope    a ramp between two elevations, taking its rise from the cells on
--            either side rather than from a height of its own.
-- ---------------------------------------------------------------------------

return {
  version = 1,
  source = "pret/pokeemerald include/constants/metatile_behaviors.h",

  -- The three added classes, carried here as well so a host whose TileShape
  -- predates them still resolves something rather than dropping the cell.
  classes = {
    bridge = { h = 4, art = "top" },
    log    = { h = 2, art = "top" },
    slope  = { h = 0, art = "top" },
  },

  -- Emerald's four reserved elevations, by name (include/global.fieldmap.h).
  elevation = {
    transition = 0,   -- "matches anything": ramps, stairs, the lip of a cliff
    surf       = 1,   -- the water surface
    default    = 3,   -- ordinary ground -- the datum
    multi      = 15,  -- "do not change the walker's level here": a bridge deck
  },

  -- behaviour byte -> class.  165 rows, covering every
  -- behaviour Emerald defines.
  behaviour = {
    -- ORDINARY GROUND.  MB_NORMAL is most of the world, and what a
  -- normal cell BECOMES is decided by its collision bit and its layer type
  -- rather than here -- see Gen3.classAt.  A cave floor, a mountain top and
  -- an indoor-encounter floor are all just floor to a renderer.
    [0x00] = "ground",      -- MB_NORMAL
    [0x07] = "ground",      -- MB_SHORT_GRASS
    [0x08] = "ground",      -- MB_CAVE
    [0x0A] = "ground",      -- MB_NO_RUNNING
    [0x0B] = "ground",      -- MB_INDOOR_ENCOUNTER
    [0x0C] = "ground",      -- MB_MOUNTAIN_TOP
    [0x1B] = "ground",      -- MB_STAIRS_OUTSIDE_ABANDONED_SHIP
    [0x1C] = "ground",      -- MB_SHOAL_CAVE_ENTRANCE
    [0x48] = "ground",      -- MB_TRICK_HOUSE_PUZZLE_8_FLOOR

    -- SAND.  Deep sand records footprints and slows you down; none of
  -- it changes shape.
    [0x06] = "ground",      -- MB_DEEP_SAND
    [0x21] = "ground",      -- MB_SAND
    [0x25] = "ground",      -- MB_FOOTPRINTS

    -- ICE.  Slippery, and flat: the crack state is a texture, not a
  -- form.
    [0x20] = "ground",      -- MB_ICE
    [0x26] = "ground",      -- MB_THIN_ICE
    [0x27] = "ground",      -- MB_CRACKED_ICE

    -- FORCED MOVEMENT.  The Trick House conveyors and the ice-puzzle
  -- slides -- ordinary floor that walks you across itself.
    [0x40] = "ground",      -- MB_WALK_EAST
    [0x41] = "ground",      -- MB_WALK_WEST
    [0x42] = "ground",      -- MB_WALK_NORTH
    [0x43] = "ground",      -- MB_WALK_SOUTH
    [0x44] = "ground",      -- MB_SLIDE_EAST
    [0x45] = "ground",      -- MB_SLIDE_WEST
    [0x46] = "ground",      -- MB_SLIDE_NORTH
    [0x47] = "ground",      -- MB_SLIDE_SOUTH

    -- INVISIBLE BARRIERS.  These sit on ORDINARY ART -- the
  -- edge of a cliff, the rail of a pier -- and block one direction without
  -- drawing anything at all.  Standing them up would build a wall the game
  -- never draws; what the player actually sees is the ELEVATION step beside
  -- them, and that comes through the height field for free.
    [0x30] = "ground",      -- MB_IMPASSABLE_EAST
    [0x31] = "ground",      -- MB_IMPASSABLE_WEST
    [0x32] = "ground",      -- MB_IMPASSABLE_NORTH
    [0x33] = "ground",      -- MB_IMPASSABLE_SOUTH
    [0x34] = "ground",      -- MB_IMPASSABLE_NORTHEAST
    [0x35] = "ground",      -- MB_IMPASSABLE_NORTHWEST
    [0x36] = "ground",      -- MB_IMPASSABLE_SOUTHEAST
    [0x37] = "ground",      -- MB_IMPASSABLE_SOUTHWEST
    [0xC0] = "ground",      -- MB_IMPASSABLE_SOUTH_AND_NORTH
    [0xC1] = "ground",      -- MB_IMPASSABLE_WEST_AND_EAST

    -- WARPS, HOLES AND ESCALATORS.  Floor you step onto and leave
  -- from.  Berry soil is here too: the plant growing in it is an object
  -- sprite, not part of the metatile.
    [0x0D] = "ground",      -- MB_BATTLE_PYRAMID_WARP
    [0x0E] = "ground",      -- MB_MOSSDEEP_GYM_WARP
    [0x0F] = "ground",      -- MB_MT_PYRE_HOLE
    [0x29] = "ground",      -- MB_LAVARIDGE_GYM_B1F_WARP
    [0x62] = "ground",      -- MB_EAST_ARROW_WARP
    [0x63] = "ground",      -- MB_WEST_ARROW_WARP
    [0x64] = "ground",      -- MB_NORTH_ARROW_WARP
    [0x65] = "ground",      -- MB_SOUTH_ARROW_WARP
    [0x66] = "ground",      -- MB_CRACKED_FLOOR_HOLE
    [0x67] = "ground",      -- MB_AQUA_HIDEOUT_WARP
    [0x68] = "ground",      -- MB_LAVARIDGE_GYM_1F_WARP
    [0x6A] = "ground",      -- MB_UP_ESCALATOR
    [0x6B] = "ground",      -- MB_DOWN_ESCALATOR
    [0x6D] = "ground",      -- MB_WATER_SOUTH_ARROW_WARP
    [0x6E] = "ground",      -- MB_DEEP_SOUTH_WARP
    [0xA0] = "ground",      -- MB_BERRY_TREE_SOIL
    [0xD2] = "ground",      -- MB_CRACKED_FLOOR

    -- GRASS.  Tall, long, and the ash-covered grass of Route 113 --
  -- all of it flat ground wearing standing blades.
    [0x02] = "grass",       -- MB_TALL_GRASS
    [0x03] = "grass",       -- MB_LONG_GRASS
    [0x09] = "grass",       -- MB_LONG_GRASS_SOUTH_EDGE
    [0x24] = "grass",       -- MB_ASHGRASS

    -- WATER.  Every surfable behaviour, plus the four currents, the
  -- seaweed and the reflection strip drawn under a bridge.  Puddles, shallow
  -- water and the Lavaridge hot springs are water as well: they recess, they
  -- reflect, and a puddle meshed as ground is a blue square lying on the
  -- road.
    [0x10] = "water",       -- MB_POND_WATER
    [0x11] = "water",       -- MB_INTERIOR_DEEP_WATER
    [0x12] = "water",       -- MB_DEEP_WATER
    [0x13] = "waterfall",   -- MB_WATERFALL
    [0x14] = "water",       -- MB_SOOTOPOLIS_DEEP_WATER
    [0x15] = "water",       -- MB_OCEAN_WATER
    [0x16] = "water",       -- MB_PUDDLE
    [0x17] = "water",       -- MB_SHALLOW_WATER
    [0x18] = "water",       -- MB_UNUSED_SOOTOPOLIS_DEEP_WATER
    [0x19] = "water",       -- MB_NO_SURFACING
    [0x1A] = "water",       -- MB_UNUSED_SOOTOPOLIS_DEEP_WATER_2
    [0x22] = "water",       -- MB_SEAWEED
    [0x28] = "water",       -- MB_HOT_SPRINGS
    [0x2A] = "water",       -- MB_SEAWEED_NO_SURFACING
    [0x2B] = "water",       -- MB_REFLECTION_UNDER_BRIDGE
    [0x50] = "water",       -- MB_EASTWARD_CURRENT
    [0x51] = "water",       -- MB_WESTWARD_CURRENT
    [0x52] = "water",       -- MB_NORTHWARD_CURRENT
    [0x53] = "water",       -- MB_SOUTHWARD_CURRENT

    -- JUMP LEDGES, all eight directions.  The direction is in the
  -- behaviour's own NAME here -- on Gen 2 it has to be read off the
  -- neighbouring cell's collision class (TileShape's HOP_LIP), which is why
  -- that rule exists at all.
    [0x38] = "ledge",       -- MB_JUMP_EAST
    [0x39] = "ledge",       -- MB_JUMP_WEST
    [0x3A] = "ledge",       -- MB_JUMP_NORTH
    [0x3B] = "ledge",       -- MB_JUMP_SOUTH
    [0x3C] = "ledge",       -- MB_JUMP_NORTHEAST
    [0x3D] = "ledge",       -- MB_JUMP_NORTHWEST
    [0x3E] = "ledge",       -- MB_JUMP_SOUTHEAST
    [0x3F] = "ledge",       -- MB_JUMP_SOUTHWEST

    -- SLOPES.  A muddy slope needs the Acro Bike to climb and a bumpy
  -- one bounces you up it; both are RAMPS between two elevations, and the
  -- cells on either side are what give them their rise.
    [0xD0] = "slope",       -- MB_MUDDY_SLOPE
    [0xD1] = "slope",       -- MB_BUMPY_SLOPE

    -- BRIDGES AND LOG RAFTS.  A bridge cell carries elevation 15
  -- (MULTI_LEVEL) and spans water at elevation 1 -- the one place Emerald
  -- states real stacked geometry outright, and 592 cells of Route 110's
  -- cycling road are exactly that.  Pacifidlog's logs get their own class
  -- because they FLOAT: the town draws every log in three vertical states
  -- and a raft rides barely clear of the sea.
    [0x70] = "bridge",      -- MB_BRIDGE_OVER_OCEAN
    [0x71] = "bridge",      -- MB_BRIDGE_OVER_POND_LOW
    [0x72] = "bridge",      -- MB_BRIDGE_OVER_POND_MED
    [0x73] = "bridge",      -- MB_BRIDGE_OVER_POND_HIGH
    [0x74] = "log",         -- MB_PACIFIDLOG_VERTICAL_LOG_TOP
    [0x75] = "log",         -- MB_PACIFIDLOG_VERTICAL_LOG_BOTTOM
    [0x76] = "log",         -- MB_PACIFIDLOG_HORIZONTAL_LOG_LEFT
    [0x77] = "log",         -- MB_PACIFIDLOG_HORIZONTAL_LOG_RIGHT
    [0x78] = "bridge",      -- MB_FORTREE_BRIDGE
    [0x7A] = "bridge",      -- MB_BRIDGE_OVER_POND_MED_EDGE_1
    [0x7B] = "bridge",      -- MB_BRIDGE_OVER_POND_MED_EDGE_2
    [0x7C] = "bridge",      -- MB_BRIDGE_OVER_POND_HIGH_EDGE_1
    [0x7D] = "bridge",      -- MB_BRIDGE_OVER_POND_HIGH_EDGE_2
    [0x7F] = "bridge",      -- MB_BIKE_BRIDGE_OVER_BARRIER

    -- RAILS.  The Mauville cycling-road barriers and the New Mauville
  -- fences: waist-high, see-through, and not walls.
    -- A RAIL IS A PLANK YOU WALK ALONG, NOT A RAILING YOU WALK PAST.
    --
    -- These four rows said `fence`, and they were unreachable: `fence` is in
    -- `standing` below, so a PASSABLE cell carrying one fell straight back to
    -- `ground`.  51 of Route 119's 55 rail cells are passable -- you walk on
    -- them -- so 51 of them meshed as two courses of solid pavement standing
    -- in the river.
    --
    -- And `fence` was the wrong answer even where it did apply.  Route 119's
    -- rails are the white plank walkways over its water: a narrow deck on
    -- dark posts, drawn end to end in runs, which is a BRIDGE.  The map's
    -- other six crossings already reach `bridge` through the elevation rule
    -- (see Gen3.classAt, ELEV_MULTI) and these are the same structure by
    -- another statement -- the only difference is that the cartridge names
    -- these ones instead of leaving them to the elevation field.
    --
    -- `bridge` is not in `standing`, which is what makes the row apply at
    -- all: a deck is walkable by definition.  Route 119 and the Safari
    -- Zone's south gate are the only maps in Hoenn that carry these.
    [0xD3] = "bridge",      -- MB_ISOLATED_VERTICAL_RAIL
    [0xD4] = "bridge",      -- MB_ISOLATED_HORIZONTAL_RAIL
    [0xD5] = "bridge",      -- MB_VERTICAL_RAIL
    [0xD6] = "bridge",      -- MB_HORIZONTAL_RAIL

    -- DOORS AND LADDERS.  A door is part of the facade and must rise
  -- WITH the wall it is cut into, or every building in Hoenn ends up with a
  -- doorway-shaped notch punched through it.
    [0x60] = "wall",        -- MB_NON_ANIMATED_DOOR
    [0x61] = "wall",        -- MB_LADDER
    [0x69] = "wall",        -- MB_ANIMATED_DOOR
    [0x6C] = "wall",        -- MB_WATER_DOOR
    [0x8B] = "wall",        -- MB_CLOSED_SOOTOPOLIS_DOOR
    [0x8C] = "wall",        -- MB_TRICK_HOUSE_PUZZLE_DOOR
    [0x8D] = "wall",        -- MB_PETALBURG_GYM_DOOR
    [0xBE] = "wall",        -- MB_SECRET_BASE_BREAKABLE_DOOR
    [0xEA] = "wall",        -- MB_SKY_PILLAR_CLOSED_DOOR

    -- FURNITURE.  This is the part Gen 2 cannot express at all --
  -- its collision classes know about counters and bookshelves and nothing
  -- else -- while Emerald names the television, the PC, the vase, the trash
  -- can, the Pokeblock feeder and the slot machine one at a time.
    [0x80] = "counter",     -- MB_COUNTER
    [0x83] = "console",     -- MB_PC
    [0x84] = "console",     -- MB_CABLE_BOX_RESULTS_1
    [0x85] = "wall",        -- MB_REGION_MAP
    [0x86] = "console",     -- MB_TELEVISION
    [0x87] = "prop",        -- MB_POKEBLOCK_FEEDER
    [0x89] = "prop",        -- MB_SLOT_MACHINE

    -- A ROULETTE TABLE IS DRAWN FROM ABOVE, AND `prop` STANDS IT ON EDGE.
    --
    -- MOTIVATED BY THE TWO ROULETTE TABLES ON THE FLOOR OF
    -- MauvilleCity_GameCorner, (14..15, 6..8) AND (18..19, 6..8) -- "the
    -- game tables are appearing vertically instead of on the ground".
    --
    -- `prop` is not a shape.  Every other row in this block names a shape
    -- the mod models -- a counter, a bookcase, a television, a vase -- and
    -- `prop` is what a row says when the cartridge has named an
    -- INTERACTION and the mod has no model for it.  It resolves to the
    -- per-pixel STANDEE pool (`TileShape.ART.prop == "billboard"`,
    -- `Structures.PINNED_DEPTH.prop == 5`), where
    -- `Structures.extractObjects` floods the whole connected cluster and
    -- `Structures.buildVolume` maps every drawn pixel ROW onto a voxel of
    -- HEIGHT (`y = baseY + c.lowY - ly`).  Six cells of roulette table
    -- therefore came out as ONE 32x48px plane standing on its south edge:
    -- measured, the two clusters span y 0..46 in a room whose walls are 32,
    -- and the map draws 15,888 vertical object quads against 454
    -- horizontal.
    --
    -- WHAT THE DRAWING SAYS.  Metatile 546, the table's north-west cell,
    -- mirrors TOP TO BOTTOM about its own row 8.5 at 0.955 of its pixels
    -- (7 row pairs, exact palette-index equality) -- rows 4/13, 5/12, 6/11,
    -- 7/10 and 8/9 are identical and 3/14 differs in one pixel.  That is a
    -- WHEEL SEEN FROM DIRECTLY ABOVE and it cannot be a front face: nothing
    -- drawn face-on in a Gen 3 interior is its own reflection in a
    -- horizontal line, because a standing object has a top, a body and a
    -- base (the slot machine's own 548 reads 0.420, 556 reads 0.607, 564
    -- reads 0.552).  547/554/555 continue the table as the betting grid,
    -- also from above; 562/563 close it with six rows of front apron and
    -- then four rows of the room's own carpet.  That is a table lying on
    -- the floor, drawn top-down, exactly like
    -- MossdeepCity_GameCorner_1F's tables at (2..3, 7) and (7..8, 7) --
    -- which the pixel carve in `Gen3.buildScenery` already calls `tabletop`
    -- because Emerald leaves their behaviour byte MB_NORMAL and the carve
    -- gets to answer.  Mauville's carry MB_ROULETTE, the row below
    -- pre-empted the carve, and the two game corners in Hoenn ended up
    -- modelled as opposites.
    --
    -- AND THE CARTRIDGE SAYS IT TOO, IN THE PLACE THIS MOD ALREADY READS.
    -- `Structures.standGen3Furniture` (g3-carcass-239) established where
    -- Emerald states that a piece of indoor furniture STANDS: the part over
    -- your head goes in the above-player layer of the WALKABLE ROW BEHIND
    -- the object, drawn right across the tile row nearest it
    -- (`stats.bot2 >= 128`).  Asked of every indoor blocked cell in all 518
    -- maps whose class comes from a behaviour row that says `prop` -- which
    -- is these four objects and nothing else in Hoenn -- the answer is
    -- exactly bimodal, with no threshold in it to fit:
    --
    --   MB_SLOT_MACHINE  (2..3, 6..9) and (7..8, 6..9)   128, 128  of 128
    --   MB_ROULETTE      (14..15, 6..8) and (18..19,6..8)  0,   0  of 128
    --
    -- The slot machines have a full lid drawn over the player in the
    -- walkable row at cy = 5 (metatile 548/549, 208 above-player pixels,
    -- bot2 = 128) and are drawn face-on, so they KEEP the standee.  The
    -- roulette tables have nothing above the player anywhere behind them --
    -- the row at cy = 5 is the plain floor metatile 514, bot2 = 0 -- so
    -- they are not drawn face-on and must not be stood up.
    --
    -- `tabletop` is a 12px box wearing its own cell's art on its LID, one
    -- cell of drawing per cell of box, 1:1 (`ChunkMesher`'s non-upright
    -- branch takes `topTile = tile`).  It is deliberately NOT `carcass`:
    -- a carcass folds its picture UP ITS SOUTH FACE, which would put the
    -- roulette wheel on a vertical panel again.  `standGen3Furniture` still
    -- gets to look at these six-cell objects afterwards and declines to
    -- stand them, on the same test, which is the reading confirming itself
    -- rather than a special case.
    --
    -- ALTERNATIVE READING CONSIDERED AND REJECTED: the role table's
    -- `art`/`cap`/`face` fields (546 is "brow" cap 0 face 1, 555 is
    -- "surface" cap 16).  Those describe TERRAIN -- where a drop turns over
    -- from top to wall -- and g3-carcass-239 already measured them as no
    -- discriminator for furniture.  A roulette table is not terrain.
    [0x8A] = "tabletop",    -- MB_ROULETTE
    [0x8E] = "wall",        -- MB_RUNNING_SHOES_INSTRUCTION
    [0x8F] = "wall",        -- MB_QUESTIONNAIRE
    [0xB0] = "console",     -- MB_SECRET_BASE_PC
    [0xB1] = "console",     -- MB_SECRET_BASE_REGISTER_PC
    [0xC5] = "console",     -- MB_PLAYER_ROOM_PC_ON
    [0xC7] = "wall",        -- MB_SECRET_BASE_POSTER
    [0xE0] = "bookcase",    -- MB_PICTURE_BOOK_SHELF
    [0xE1] = "bookcase",    -- MB_BOOKSHELF
    [0xE2] = "bookcase",    -- MB_POKEMON_CENTER_BOOKSHELF
    [0xE3] = "cylinder",    -- MB_VASE
    [0xE4] = "can",         -- MB_TRASH_CAN
    [0xE5] = "bookcase",    -- MB_SHOP_SHELF
    [0xE6] = "wall",        -- MB_BLUEPRINT
    [0xE7] = "console",     -- MB_CABLE_BOX_RESULTS_2
    [0xE8] = "console",     -- MB_WIRELESS_BOX_RESULTS
    [0xE9] = "console",     -- MB_TRAINER_HILL_TIMER

    -- SECRET BASES.  The cave and tree entrance spots, the
  -- decoration footprints and the mats.  270 of the game's 692 metatile
  -- labels are secret-base furniture, which is a large slice of the
  -- vocabulary for a part of the game most players see once.
    [0x01] = "wall",        -- MB_SECRET_BASE_WALL
    [0x90] = "wall",        -- MB_SECRET_BASE_SPOT_RED_CAVE
    [0x91] = "wall",        -- MB_SECRET_BASE_SPOT_RED_CAVE_OPEN
    [0x92] = "wall",        -- MB_SECRET_BASE_SPOT_BROWN_CAVE
    [0x93] = "wall",        -- MB_SECRET_BASE_SPOT_BROWN_CAVE_OPEN
    [0x94] = "wall",        -- MB_SECRET_BASE_SPOT_YELLOW_CAVE
    [0x95] = "wall",        -- MB_SECRET_BASE_SPOT_YELLOW_CAVE_OPEN
    [0x96] = "tree",        -- MB_SECRET_BASE_SPOT_TREE_LEFT
    [0x97] = "tree",        -- MB_SECRET_BASE_SPOT_TREE_LEFT_OPEN
    [0x98] = "tree",        -- MB_SECRET_BASE_SPOT_SHRUB
    [0x99] = "tree",        -- MB_SECRET_BASE_SPOT_SHRUB_OPEN
    [0x9A] = "wall",        -- MB_SECRET_BASE_SPOT_BLUE_CAVE
    [0x9B] = "wall",        -- MB_SECRET_BASE_SPOT_BLUE_CAVE_OPEN
    [0x9C] = "tree",        -- MB_SECRET_BASE_SPOT_TREE_RIGHT
    [0x9D] = "tree",        -- MB_SECRET_BASE_SPOT_TREE_RIGHT_OPEN
    [0xB2] = "prop",        -- MB_SECRET_BASE_SCENERY
    [0xB3] = "ground",      -- MB_SECRET_BASE_TRAINER_SPOT
    [0xB4] = "prop",        -- MB_SECRET_BASE_DECORATION
    [0xB5] = "prop",        -- MB_HOLDS_SMALL_DECORATION
    [0xB7] = "wall",        -- MB_SECRET_BASE_NORTH_WALL
    [0xB8] = "prop",        -- MB_SECRET_BASE_BALLOON
    [0xB9] = "wall",        -- MB_SECRET_BASE_IMPASSABLE
    [0xBA] = "ground",      -- MB_SECRET_BASE_GLITTER_MAT
    [0xBB] = "ground",      -- MB_SECRET_BASE_JUMP_MAT
    [0xBC] = "ground",      -- MB_SECRET_BASE_SPIN_MAT
    [0xBD] = "ground",      -- MB_SECRET_BASE_SOUND_MAT
    [0xBF] = "prop",        -- MB_SECRET_BASE_SAND_ORNAMENT
    [0xC2] = "ground",      -- MB_SECRET_BASE_HOLE
    [0xC3] = "prop",        -- MB_HOLDS_LARGE_DECORATION
    [0xC4] = "prop",        -- MB_SECRET_BASE_TV_SHIELD
    [0xC6] = "prop",        -- MB_SECRET_BASE_DECORATION_BASE
  },

  -- ---------------------------------------------------------------------
  -- CLASSES YOU CANNOT BE STANDING INSIDE.
  --
  -- A behaviour row is a statement about the ART, and the cell's collision
  -- bit is a separate statement about whether you can walk there.  Where the
  -- two disagree the collision bit wins, because it is the one the player
  -- experiences: MB_MOUNTAIN_TOP is the crater wall in Sootopolis and a
  -- walkable rock shelf in Pacifidlog, out of the same behaviour byte.
  --
  -- So a row naming one of these classes only applies to a BLOCKED cell; on
  -- a passable one it falls back to ground.  Without the rule a profile that
  -- makes Sootopolis' rim two courses tall also makes every walkable ledge
  -- in Pacifidlog a 32px block with the player buried in it.
  --
  -- DOORS are the deliberate exception and are listed separately below: a
  -- door cell IS walkable -- you step onto it to warp -- and it has to rise
  -- with the wall it is cut into anyway, or the facade gets a doorway-shaped
  -- hole punched through it.  Gen 1 and Gen 2 reach the same conclusion by a
  -- different route (Structures' door fold).
  standing = {
    wall = true, cliff = true, tree = true, shell = true, column = true,
    bookcase = true, counter = true, console = true, prop = true,
    cylinder = true, can = true, fence = true, billboard = true,
    signpost = true, post = true, planter = true, canopy = true,
    table_ = true, desk = true,
    -- `tabletop` joins the set with MB_ROULETTE above, and it is a no-op on
    -- the cartridge as shipped: all twelve MB_ROULETTE cells in Hoenn --
    -- MauvilleCity_GameCorner (14..15, 6..8) and (18..19, 6..8), the only
    -- twelve there are -- are blocked, so this branch never fires on them.
    -- It is here because the set's whole job is "this class only applies
    -- where the player cannot be", and a `tabletop` on a walkable cell
    -- would raise a 12px riser under the player's feet, which is the one
    -- kind of artefact this file's own comment says the set exists to stop.
    -- No behaviour row resolved to `tabletop` before MB_ROULETTE did, so
    -- nothing else in Hoenn, Kanto, Johto or Prism can reach this line: the
    -- only other `tabletop` in the file is the PIN on gTileset_
    -- BrendansMaysHouse's dining cloth (538/539/546/547), and a pin returns
    -- from `classAt`'s first arm, long before this test.
    tabletop = true,
  },

  -- ---------------------------------------------------------------------
  -- THE FOUR GRASSES, SEPARATED.
  --
  -- Emerald writes four different behaviour bytes on things this mod had
  -- been calling one class, and they are four different DRAWINGS.  The
  -- shape class above stays `grass` for all four -- it is what says "flat
  -- walkable ground" to eight separate passes in Structures, Gen3 and
  -- TileShape, and moving it would move terrain -- so the separation is
  -- here, on the one question the class cannot answer: what, if anything,
  -- does this drawing state is STANDING on the cell.
  --
  -- Measured over all 518 maps, on the shape surface (the atlas with the
  -- tileset's own ground colours carved to alpha 0 -- Gen3.shapeDataForMap),
  -- as opaque pixels out of the cell's 256, and as pixels drawn on the
  -- ABOVE-PLAYER layer out of 256:
  --
  --   beh  what            metatile(s)          cover     above-player
  --   ---- --------------- -------------------- --------- ------------
  --   0x00 the lawn        general m1           0/256     0
  --   0x02 TALL GRASS      general m13          71/256    0
  --        (+ tree fringe) general m454/455     85,86/256 23
  --   0x03 LONG GRASS      Fortree m21          237/256   0
  --   0x09 its south edge  Fortree m520         193/256   0
  --   0x24 ASH GRASS       Fallarbor m522       150/256   0
  --                        JaggedPass m519      256/256   0
  --
  -- 0x02 is the only one of the four with a SPARSE silhouette, and it is
  -- one drawing: general tileset metatile 13, byte for byte the same on
  -- Route 101, 110, 112, 114, 121, Petalburg Woods, Mt Pyre, the Battle
  -- Palace corridor and Verdanturf's Battle Tent -- cover 71/256 and the
  -- row profile 0,1,1,4,5,4,4,4,5,11,5,4,5,9,7,2 identical across six
  -- tileset pairs.  Two dense base bars (rows 9 and 13) with blade strokes
  -- scattered above them: a PLAN of a grass surface that has blades in it.
  --
  -- 0x03/0x09 are not blades at all.  Long grass fills its cell -- 237 of
  -- 256, in colours the lawn never uses -- and its south edge draws the
  -- MASS'S OWN BOTTOM EDGE tapering away over its last four rows
  -- (16,16,16,16,16,16,16,16,16,15,15,12,5,2,0,0).  That is a hedge you
  -- wade into, drawn with a visible front, and standing it as tufts would
  -- build a solid opaque block over Route 119.
  --
  -- 0x24 is ash, not grass.  Route 113's ash grass is SIX GREYS AND NO
  -- GREEN (148/139/115, 172/172/139, 115/115/74, 205/205/164, 90/90/57,
  -- 230/230/205 -- the first, second and fourth of which are exactly the
  -- three colours of the plain ash ground beside it), Jagged Pass's is the
  -- same picture in mauves, and neither has a base bar, a silhouette or a
  -- repeating quadrant.  It is a rougher, deeper layer of ash LYING ON the
  -- ground.  Standing its noise up would grow a grey bristle field over
  -- Route 113: 305 quads a cell of geometry cut from a texture.
  --
  -- So: `tuft` is the only kind that gets geometry.  `mass` and `ash` are
  -- named so that they are visibly DECIDED rather than swept up with 0x02,
  -- and so the next reader can find the measurement that decided them.
  grass_kind = {
    [0x02] = "tuft",   -- MB_TALL_GRASS
    [0x03] = "mass",   -- MB_LONG_GRASS
    [0x09] = "mass",   -- MB_LONG_GRASS_SOUTH_EDGE
    [0x24] = "ash",    -- MB_ASHGRASS
  },

  -- The behaviours that are doors, ladders and shutters -- walkable, and
  -- part of the facade regardless.
  doors = {
    [0x60] = true,   -- MB_NON_ANIMATED_DOOR
    [0x61] = true,   -- MB_LADDER
    [0x69] = true,   -- MB_ANIMATED_DOOR
    [0x6C] = true,   -- MB_WATER_DOOR
    [0x8B] = true,   -- MB_CLOSED_SOOTOPOLIS_DOOR
    [0x8C] = true,   -- MB_TRICK_HOUSE_PUZZLE_DOOR
    [0x8D] = true,   -- MB_PETALBURG_GYM_DOOR
    [0xBE] = true,   -- MB_SECRET_BASE_BREAKABLE_DOOR
    [0xEA] = true,   -- MB_SKY_PILLAR_CLOSED_DOOR
  },

  -- ---------------------------------------------------------------------
  -- HOW FAR A BRIDGE STANDS OVER WHAT IT SPANS, in courses.
  --
  -- Emerald states this outright and it is easy to miss: the bridge
  -- behaviours are an ORDERED HEIGHT INDEX. MetatileBehavior_GetBridgeType
  -- maps MB_BRIDGE_OVER_POND_LOW / _MED / _HIGH to 0 / 1 / 2, which is why
  -- Route 120 carries a low bridge across its southern pond and a high one
  -- across the northern half of the same water.
  -- ---------------------------------------------------------------------
  bridge_lift = {
    [0x70] = 2,   -- MB_BRIDGE_OVER_OCEAN -- Route 110's cycling road
    [0x71] = 1,   -- MB_BRIDGE_OVER_POND_LOW
    [0x72] = 2,   -- MB_BRIDGE_OVER_POND_MED
    [0x73] = 3,   -- MB_BRIDGE_OVER_POND_HIGH
    [0x7A] = 2, [0x7B] = 2,   -- the MED bridge's two edge pieces
    [0x7C] = 3, [0x7D] = 3,   -- and the HIGH bridge's
    [0x7F] = 2,   -- MB_BIKE_BRIDGE_OVER_BARRIER
    [0x78] = 2,   -- MB_FORTREE_BRIDGE -- the rope walk between the houses
  },

  -- HOW MANY COURSES A SPAN RIDES ABOVE THE STOREY IT IS ON.  STATED.
  --
  -- Reported: "the bike path isnt tall enough needs to be about 2 blocks
  -- taller".  This number is the REPORT'S, not a measurement, and it is
  -- written here rather than dressed up as one.  What was looked for and not
  -- found, so nobody re-derives it:
  --
  --   * `bridge_lift` already states the cartridge's own answer and it is the
  --     height the road ALREADY has -- MB_BRIDGE_OVER_OCEAN is 2, and
  --     `Gen3.groundHeight`'s causeway arm and `levelGen3Decks`' elevation
  --     rank independently arrive at the same 32px.  The ROM says two
  --     courses and the road is at two courses.
  --   * the DRAWING states less, not more: the road's south fascia is ONE
  --     cell row of art (metatile 774/777 on Route 110's row 58) against 36px
  --     of exposed side at the height it already stands, and the timber piers
  --     under it are drawn about a cell and a half tall.  Raising the deck
  --     puts MORE side under it than Emerald ever drew, not less.
  --
  -- So there is no derivation here and none is claimed.  It is keyed on
  -- MB_BIKE_BRIDGE_OVER_BARRIER (0x7F) -- Emerald's own word for a bike
  -- bridge that flies over something that would otherwise stop you, and the
  -- one behaviour in Hoenn that names the Seaside Cycling Road and nothing
  -- else: 6 cells, all of them inside the single 598-cell deck run on Route
  -- 110, and no other map in the region lays one.  Route 119's two
  -- MB_BRIDGE_OVER_OCEAN spans (10 and 6 cells), Route 120's rope bridges,
  -- Fortree's walkway, Shoal Cave's two decks and Victory Road's crossings
  -- state no 0x7F and are not touched.
  span_freeboard = {
    [0x7F] = 2,   -- MB_BIKE_BRIDGE_OVER_BARRIER -- the cycling road
  },

  -- ---------------------------------------------------------------------
  -- PER-TILESET AND PER-MAP OVERRIDES
  --
  -- Everything above is true of all of Hoenn.  These are the places where
  -- the ART says something the data does not, and they are deliberately
  -- few: the behaviour byte, the layer type and the elevation field between
  -- them get the whole region standing correctly, and a profile's job is
  -- only to correct a proportion.
  --
  -- Resolution order is primary tileset, then secondary, then the map by
  -- name (lib/Gen3.lua) -- most general to most specific, each overlaying
  -- the last.  Names are pokeemerald's, resolved through data/gen3_maps.lua,
  -- because the engine keys a pair by ROM ADDRESS and an address is a fact
  -- about one cartridge rather than about Hoenn.
  --
  -- Keys a profile may set:
  --   course      pixels per elevation RANK (default 16, one cell).  Emerald
  --               labels its levels rather than counting them -- a map uses
  --               whichever of 0..15 it likes and skips the rest -- so the
  --               mod ranks the levels a map actually uses and spaces the
  --               ranks evenly.  This is the spacing.
  --   behaviour   rows to add or replace for this tileset only; `false`
  --               withdraws a row and sends the cell back to the structural
  --               rule.
  --   bridge_lift as above, per tileset.
  --   cover       the class a blocked cell with above-player art becomes.
  -- ---------------------------------------------------------------------
  tilesets = {

    -- SOOTOPOLIS: a city built down the inside of a volcanic crater.  The
    -- most COVERED-heavy outdoor map in the game -- 2914 of its 3600 cells
    -- against 681 NORMAL -- because almost everything in it is a terrace the
    -- player walks over.  Its verticality is NOT in the elevation field:
    -- only ONE real level appears (3), with everything else 0 or the surf,
    -- so the crater is entirely in the art and the run measurement is what
    -- builds it.  What the profile is for here is the rim: MB_MOUNTAIN_TOP
    -- is the crater WALL, two courses rather than one, or the city sits in a
    -- saucer instead of a caldera.
        -- SLATEPORT: the open-air market.  The awning metatiles -- canopy top
    -- and hanging skirt -- are stood up as floating decks on the drawn
    -- poles (Structures.buildGen3Stalls).
    gTileset_Slateport = {
      stall_awning = { 517, 525, 526, 527, 551, 565, 559, 760, 761, 762 },
    },

    -- EVERY POKEMON CENTER'S STAIRCASE (34 maps share this tileset).
    -- The 1F flight, a 2x3 block in the west wall.  Emerald says nothing
    -- about it: five of its six cells are MB_NORMAL and walkable, so the
    -- steps lay painted flat on the floor, and the sixth -- 648 -- tripped
    -- the furniture detector and stood up as a 12px TABLETOP in the middle
    -- of them.
    --
    -- The drawing says which way it climbs.  Read as luminance, the treads
    -- are horizontal bands in three column groups (x0-6, x8-14, x16-30),
    -- each group starting three rows lower than the one to its west: a
    -- flight climbing WEST, into the wall.  `flights` re-grounds the region
    -- as a ramp of tile-column steps (Structures.buildGen3Flights) so it is
    -- walked up instead of walked over.
    --
    -- The 2F half (664/665/672/673/680/681) is the same well seen from
    -- above and DESCENDS; a hole cut below an interior floor needs the room
    -- plane to close around it, which is not built, so 2F is left flat --
    -- with 672 pinned `ground` below so it at least stops being a slab.
    gTileset_PokemonCenter = {
      flights = {
        { dir = "w", tiles = { 640, 641, 648, 649, 656, 657 } },
      },
    },

gTileset_Sootopolis = {
      behaviour = { [0x0C] = "cliff" },   -- MB_MOUNTAIN_TOP
      -- Every roof in the crater is drawn as a dark CONE over an octagonal
      -- body.  Built as sheds they lean into squat lozenges; this says the
      -- pointed style exists here, and the octagon trim picks which
      -- buildings actually taper (Structures: tent test).
      tent_roof = true,
    },

    -- LAVARIDGE: Mt Chimney, Jagged Pass and the Fiery Path.  The volcano's
    -- flank is drawn as one continuous scree -- the same rock motif the
    -- whole way down, with no contour band for the terrace reconstruction
    -- to chain into levels.  Given nothing to stop at it levelled Jagged
    -- Pass almost entirely to its ceiling: 26 of 46 rows modal 80px, 9 more
    -- at 0, in no order.  A plateau with pits in the path, not a descent.
    --
    -- The ROM states ONE walkable level for both Jagged Pass and Mt Chimney
    -- (levels=1, every walkable cell ELEV_DEFAULT), so one level is the
    -- faithful answer.  The relief that IS stated -- the ledges you hop
    -- down, the rock walls, the cable-car pylons -- still builds.
    -- gTileset_Lavaridge (Jagged Pass, Mt Chimney, Lavaridge, Route 112).
    -- `drawn_terraces = false` USED TO BE HERE, on the grounds that the ROM
    -- reports levels=1 for these maps -- every walkable cell ELEV_DEFAULT --
    -- so one plane was the faithful answer.  That is still true of the
    -- CARTRIDGE, and it is why the flag was right when the terrace pass
    -- could only raise whole tiers by one course each.
    --
    -- It is not right for the STAIRS.  Mt Chimney draws an eight-cell flight
    -- across row 33 and five grated step plates through its ash banks, and
    -- with the pass switched off entirely none of them could climb: the
    -- steps lay flat on flat ground, leading nowhere, which is exactly what
    -- the drawing does not say.  A flight cannot raise anything unless the
    -- ground beyond it rises too, so stairs and terraces stand or fall
    -- together and the gate has to come off for either to work.
    gTileset_Lavaridge = {},

    -- EVER GRANDE: the Victory Road approach and the League plateau, with
    -- 96 cells of waterfall.  Three real levels (3, 5, 7) and 2069 cells of
    -- scenery at elevation 0 -- the cliffs.  Same rim treatment as
    -- Sootopolis: the plateau's edge is a wall of rock, not a kerb.
    gTileset_EverGrande = {
      -- height from the cartridge, not the drawing (see the maps table).
      -- One map uses this tileset, so pinning it here is safe.
      elevation_height = true, drawn_terraces = false,
      behaviour = { [0x0C] = "cliff" },
    },

    -- METEOR FALLS and the caves: MB_CAVE is the mouth, not the floor, and
    -- the rock around it is drawn as one mass.  Nothing to correct -- listed
    -- so the next person does not have to re-derive that.
    -- THE CAVES.  Their blocked rock is a mass with a top, not a building
    -- facade -- see Structures.buildGen3RockPlateaus for the measurement
    -- that made this necessary (Granite Cave 1F read `fromRepeat` with a
    -- 16px period, because the floor's hatch texture has one).
    --
    -- ...and `use_elevation`, which is the OTHER half of a cave.  Indoors
    -- the elevation field is normally discarded, because indoors Emerald
    -- uses it for sprite priority -- which side of a bed you draw on -- and
    -- ranking that into courses stands a step in the middle of a carpet.
    -- A cave is the exception: its levels are real terraces.  Measured, the
    -- difference is unmistakable.  Victory Road 1F carries 206 cells at
    -- level 4 in ten connected REGIONS, the largest 61 cells; Meteor Falls
    -- 36 in two; Shoal Cave 66 in one.  Pokemon Center 1F carries exactly
    -- ONE cell at level 4 -- that is the priority flag, and it stays
    -- discarded.
    --
    -- Turning this on gives three things at once: the walkable floor sits
    -- at its own tier instead of all on the datum, so a terrace's ground is
    -- level with the cliff edge beside it; ELEV_MULTI cells (Victory Road
    -- has 30, Meteor Falls 6) become real bridge decks a course over what
    -- they span; and because entities carry their own elevation, a walker
    -- passes UNDER those bridges instead of being lifted onto them.
    gTileset_MeteorFalls = { rock_plateau = true, use_elevation = true },
    gTileset_Cave = { rock_plateau = true, use_elevation = true },

    -- PACIFIDLOG: a town of rafts.  263 of its 800 cells are
    -- MB_MOUNTAIN_TOP -- the rocky islets the houses stand on -- and 294 are
    -- open ocean.  The logs themselves are already their own class; what
    -- matters here is that the islets stay one course, because a town that
    -- floats should not have cliffs in it.
    gTileset_Pacifidlog = {},

    -- FORTREE: houses in the canopy, joined by rope bridges.  Two real
    -- levels, 3 and 4, and the 52 cells at level 4 ARE the walkway -- the
    -- cartridge even gives the player a higher sprite priority up there so
    -- they draw over the treetops.  One course of separation would put the
    -- walkway INSIDE the canopy it is supposed to cross, so the step is two.
    -- Route 119 and Route 120 share this tileset and are ordinary ground, so
    -- the override is on the CITY (see `maps` below), not here.
    gTileset_Fortree = {},

    -- UNDERWATER: the seabed.  Every cell of it is under the sea, so the
    -- water class must not fire -- MB_NORMAL down here is the floor you swim
    -- over, and treating the map as water would recess the whole thing and
    -- leave nothing to stand on.
    gTileset_Underwater = {},

  },

  -- ---------------------------------------------------------------------
  -- METATILE PINS: the only way to say "that cell is a fridge".
  --
  -- The behaviour byte cannot say it. Every kitchen unit, every chair, every
  -- table and the wall behind them is MB_NORMAL, because the byte answers
  -- what KIND OF SURFACE a cell is and furniture is not a kind of surface.
  -- The layer type cannot either: it separates wall from furniture across
  -- most of a room but not all of it, and a rule that flattens a few wall
  -- cells is worse than no rule at all.
  --
  -- So interiors are hand-pinned per tileset, exactly the way the Gen 1 and
  -- Gen 2 profiles pin tile ids in data/voxel_heights.lua. A Gen 3 metatile
  -- id is stable within its tileset, and the key here is the tileset's
  -- pokeemerald NAME, resolved through data/gen3_maps.lua.
  --
  -- TWO RULES LEARNED THE HARD WAY:
  --
  -- 1. PIN THE FRONT ROW, NOT THE WALL BAND. Emerald draws a kitchen as two
  --    rows -- the upper doors up in the wall band, the carcasses in the row
  --    below -- and both are blocked. Unpinned they all flood into ONE region
  --    and `buildVolume` measures a single run three cells deep and 48px
  --    tall: the wall dragged forward around the fridge. Pinning the FRONT
  --    row takes it out of the flood, so the wall measures its own two cells
  --    and the units stand out in front of it. Pinning the wall band as well
  --    would be worse than doing nothing -- an authored cell leaves the
  --    flood, so each wall cell would become its own 16px box and the wall
  --    would stop being a wall.
  --
  -- 2. A PINNED CELL NEED NOT BE BLOCKED. Emerald leaves chair cells
  --    PASSABLE -- you walk over them -- so the passability guard that
  --    normally stops a walkable cell becoming furniture is bypassed for a
  --    pin. Stepping onto a chair and standing 8px up is what the drawing
  --    depicts.
  --
  -- Classes: chair / tabletop (drawn from above, art on the top face);
  -- worktop / sink / appliance / cabinet / tv (drawn face-on, art folds up
  -- the south face); bed (from above, low).
  metatiles = {

    -- LITTLEROOT TOWN's secondary tileset, which is where Professor Birch's
    -- lab lives (LAYOUT_LITTLEROOT_TOWN is gTileset_General over this one).
    gTileset_Petalburg = {
      -- ---- PROFESSOR BIRCH'S LAB, roof ---------------------------------
      -- The ventilation drum on the lab roof: a 2x2 block of drawing, the
      -- mouth ellipse and the upper barrel in 578/579 and the lower barrel
      -- and its skirt in 586/587. The lower pair sits ON the roof (the
      -- building's first row) and the upper pair is drawn above it in the
      -- walkable row behind, which is how Emerald draws everything tall.
      -- Left unpinned it lay flat: a grey rectangle inset into the roof
      -- with the mouth squashed into a bowl.
      --
      -- ONLY THE UPPER PAIR IS PINNED. The hull is carved from all four
      -- cells of art regardless (a 32px canvas reads the 2x2 block under its
      -- anchor), and pinning the lower pair as well would take them out of
      -- the structural flood -- which is the lab's own roof, and it would
      -- have come away with a two-cell hole where the chimney stands.
      [578] = "chimney", [579] = "chimney",
    },

    -- BRENDAN'S AND MAY'S HOUSE (4 maps: both children's houses, both floors).
    -- Verified against the real layouts: 1F is layout 54 (11x9), 2F is
    -- layout 55 (9x8), both on primary gTileset_Building.
    gTileset_BrendansMaysHouse = {

      -- ---- 1F, the kitchen run along the north wall --------------------
      -- Row 1 is the upper half of each unit and sits IN the wall band; it
      -- is deliberately NOT pinned (see rule 1). Row 2 is the carcass, and
      -- the fold walks north up the column so each box wears its own art low
      -- and the unit above it high.
      [568] = "appliance",  -- fridge: 560 is its upper door
      [569] = "sink",       -- basin over cupboard doors; 561 is the tap
      [570] = "worktop",    -- counter with a pot on it
      [571] = "cabinet",    -- glass-fronted dresser; 563 its upper shelves
      [572] = "cabinet",    -- and its right half

      -- THE LIVING-ROOM TELEVISION, and it was pinned `worktop` -- "the long
      -- white counter that stands out in the room" -- on a first pass that
      -- read it from its position rather than its picture. It is a white
      -- screen in a wood-framed cabinet, two cells wide, and calling it a
      -- kitchen counter stood it 18px tall in the middle of the floor with
      -- its top face to the camera: flat, grey, and no screen anywhere. The
      -- art is unambiguous once you look at it.
      [576] = "tv",
      [577] = "tv",

      -- ---- 1F, the dining set on the blue rug --------------------------
      -- The cloth is a 2x2 of drawing; the four chairs flank it, and all
      -- four chair cells are passable.
      [538] = "tabletop", [539] = "tabletop",
      [546] = "tabletop", [547] = "tabletop",
      [537] = "chair",    [540] = "chair",
      [545] = "chair",    [548] = "chair",

      -- ---- 2F -----------------------------------------------------------
      -- The bed is 3x2 cells of top-down drawing.
      [643] = "bed", [644] = "bed", [645] = "bed",
      [651] = "bed", [652] = "bed", [653] = "bed",

      -- The television stands in front of the wall; the console above it
      -- (613) stays part of the wall band, which is where it is drawn.
      [614] = "tv",

      -- the stool at the shelves
      [610] = "chair",

      -- ---- MAY'S 2F, which shares this tileset and NONE of the metatiles
      -- above. Her room is drawn from its own set, so every pin written for
      -- Brendan's room missed it and the whole floor came out as wall with
      -- one stray object -- checked against the art, cell by cell.
      --
      -- The bed stands alone in the south-east corner. As the only isolated
      -- blocked cell in the room it was being read as a SIGNPOST: a thin
      -- board on a stick where the bed should be.
      [657] = "bed",

      -- the shelf unit in the north wall band, with its things on it
      [601] = "cabinet",
    },

    -- EVERY POKEMON CENTER IN HOENN shares this tileset, so one pin set
    -- fixes the lot.  The desk is drawn as one row of counter -- two ends
    -- and a body -- but only the cell the nurse speaks across carries
    -- MB_COUNTER; the rest are MB_NORMAL and blocked, so they flooded into
    -- one region with the alcove wall BEHIND them and stood as a purple
    -- slab from floor to ceiling, the counter art repeating up its face.
    -- Pinned, the desk leaves the flood as waist-high furniture and the
    -- alcove keeps its own wall.
    gTileset_PokemonCenter = {
      [600] = "counter", [545] = "counter", [601] = "counter",
      -- ...and the 2F staircase's own stray slab.  672 is a stair TREAD --
      -- the same drawing as 1F's 648 -- and the furniture detector reads
      -- its flat pale band as a table top.  Until the descending well is
      -- built (see the `flights` profile above) it is floor, not furniture.
      [672] = "ground",
    },

    -- SLATEPORT CITY's harbour.
    gTileset_Slateport = {

      -- ---- THE MOORED SAILBOATS ---------------------------------------
      -- A 3x3 block of drawing -- hull, mast and a two-tone sail -- sitting
      -- in open water.  Every cell of it is blocked, so unpinned the flood
      -- measured one region and `buildVolume` boxed it: a 48px cube of sea
      -- with a boat printed on its lid, three times over along the quay.
      --
      -- A boat is a THIN thing seen broadside, which is what `prop` says:
      -- the drawing stands as a per-pixel slab, sail and rigging included,
      -- and the water closes behind it.  Pinned on all nine cells rather
      -- than the corner alone, because the billboard pass floods a REGION
      -- of pinned cells and builds one slab from it -- the opposite of the
      -- hull classes, where the corner pin claims its neighbours.
      [824] = "prop", [825] = "prop", [826] = "prop",
      [832] = "prop", [833] = "prop", [834] = "prop",
      [840] = "prop", [841] = "prop", [842] = "prop",

      -- ---- THE HARBOUR LIGHT ------------------------------------------
      -- Two cells wide and four tall, and round the whole way down: lamp
      -- room, gallery, shaft, splayed base.  Its lower half is blocked and
      -- its upper half is drawn on the above-player layer, so it came out
      -- as a 2x2 box with the lamp painted flat on the pavement behind it.
      --
      -- Anchors at both halves.  `canopy` on a top-left corner carves a
      -- 32px hull from the 2x2 under it; two anchors two rows apart are
      -- read as ONE 64px tower (Structures.buildCylinders).  The other six
      -- cells are `cylinder` so the group build knows the drawing is whole
      -- and does not leave a half-empty giant.
      [582] = "canopy",  [583] = "cylinder",
      [590] = "cylinder", [591] = "cylinder",
      [598] = "canopy",  [599] = "cylinder",
      [606] = "cylinder", [607] = "cylinder",

      -- ---- THE MARKET STALLS -----------------------------------------
      -- The pole rows: two bare timber poles drawn per cell, standing on
      -- the pavement.  Per-pixel slabs, so they stand where they are drawn
      -- and the awning deck (stall_awning below) floats at their tops.
      [573] = "post", [620] = "post",
    },

    -- SOOTOPOLIS: the Cave of Origin gate.
    gTileset_Sootopolis = {

      -- ---- THE GATEWAY ------------------------------------------------
      -- Three rows: a lintel spanning the opening, the dark mouth under it,
      -- and a leg either side.  The lintel and the mouth are drawn on the
      -- above-player layer and are WALKABLE -- you pass under the arch --
      -- so they came through as flat ground with the beam painted on the
      -- floor, while the legs stood as solid boxes.  A gate with its beam
      -- lying in the dirt.
      --
      -- `post` is the class for this: it extracts each CELL on its own as a
      -- per-pixel slab, so the legs stand where they are drawn, the lintel
      -- stands across the top, and the mouth stays the air it is.  A pin
      -- may be walkable -- that is the point here.
      [560] = "post", [562] = "post",   -- the legs
      [553] = "post",                   -- the lintel across the opening
      [545] = "post",                   -- the mouth and its jambs

      -- ---- THE BOLLARDS -----------------------------------------------
      -- Four cells south of the gate, each drawing TWO capped posts.  Read
      -- as wall they measured a four-tile run and stood 48px: eight stone
      -- slabs where the map draws eight little posts.
      [640] = "post",
    },

  },

  maps = {

    -- ROUTE 111'S SAND RAMPS ARE A FLIGHT, AND THE CARTRIDGE SAYS SO.
    --
    -- `MB_MUDDY_SLOPE` is Emerald's own word for a ramp: without the Acro
    -- Bike it slides the player DOWN one, and always SOUTH, so the cartridge
    -- has stated per cell that the north end is the high end.  Marking those
    -- cells as stair cells (see `markGen3Stairs`) and cutting the terrace
    -- flood at them (see `standable`) was enough to make the desert's north
    -- mesa a terrace at last -- 32 against the sand's 16 -- but a stair MARK
    -- is not a stair SHAPE.  Both cells of each ramp came out at the mesa's
    -- 32 with the whole course of drop landing in one step at the foot, and
    -- metatile 232's pale banded art drawn down the face of it: a bright slot
    -- in the cliff, reported as the mudslide being flat and a hole in the
    -- terrain.
    --
    -- `flights` is the mechanism for exactly this -- "re-grounds the region
    -- so its steps are spaced across the whole run" -- and it wants the
    -- metatile and the direction of climb.  All four muddy-slope cells in
    -- Hoenn are metatile 232 and all four are on this map.
    Route111 = { flights = { { dir = "n", tiles = { 232 } } } },

    -- THE FIERY PATH IS A CAVE ON AN OUTDOOR TILESET.
    --
    -- `rock_plateau` is what gives a cave its rock: the walls stand as a mass
    -- with their own drawing mapped once down the face instead of meshing as
    -- boxes of stretched wall.  It is carried on the TILESET, and every other
    -- cave in Hoenn uses gTileset_Cave or gTileset_MeteorFalls, so every
    -- other cave gets it.  The Fiery Path does not: it is drawn with Route
    -- 112's and Lavaridge's own tileset -- the volcanic one, shared with two
    -- OUTDOOR maps -- so the cave handling never reached it and its interior
    -- meshed as a flat slab with one-course kerbs and vertical smears down
    -- every wall.  Against Granite Cave's rounded rock in the same shot it is
    -- unmistakable.
    --
    -- Keyed on the MAP, not the tileset, because the tileset's other two maps
    -- are outdoors and this is a statement about a cave.  (`buildGen3Rock-
    -- Plateaus` refuses to run outdoors anyway -- belt and braces -- but the
    -- data should say what is true rather than lean on the guard.)
    FieryPath = { rock_plateau = true },

    -- SOOTOPOLIS is a CALDERA WITH NO WAY OUT ON FOOT.  You arrive by Dive
    -- and leave the same way; every cell of its border is crater wall.  The
    -- terrace pass protects a map's border tiers because a route's shelves
    -- join the next route and lifting one steps the seam -- but here there
    -- is no seam, and the rim is the highest ground in the town.  Guarded,
    -- the lip sank to the floor and the bowl came out inside-out.
    SootopolisCity = { terrace_free_edge = true, elevation_height = true,
                       drawn_terraces = false },

    -- ---------------------------------------------------------------------
    -- HEIGHT FROM THE CARTRIDGE, NOT FROM THE DRAWING.
    --
    -- `elevation_height` says: a walkable cell's z is its ROM ELEVATION, and
    -- the drawn-terrace flood does not run.  These four maps are pinned
    -- rather than detected because detection is what turned every purple rock
    -- into a skyscraper -- their tilesets draw houses, crater rim and cliff
    -- face in the same rock, so no art test can separate them, and the flood
    -- chained one course per blocked band until Sootopolis ran 0 at the lake
    -- to 9 at the rim on a map the cartridge says has ONE land level.
    --
    -- What the cartridge actually states, measured:
    --   Sootopolis   elev 1 (water, 601 cells) + 3 (land, 908)   -> 1 land level
    --   Mt Pyre      elev 3 (460)                                -> 1 land level
    --   Ever Grande  elev 1, 3, 5, 7                             -> 3 land levels
    --   Route 119    elev 1, 3, 4 + 15 (bridge deck)             -> 2 + a deck
    --
    -- Pinned by MAP where the tileset is shared: gTileset_Facility is Mt
    -- Pyre's secondary but also twenty-seven other maps, and gTileset_Fortree
    -- covers Faraway Island's interior as well as the grass routes.
    MtPyre_Exterior  = { elevation_height = true, drawn_terraces = false },
    MtPyre_Summit    = { elevation_height = true, drawn_terraces = false },
    Route119         = { elevation_height = true, drawn_terraces = false },


    -- The canopy walk (see gTileset_Fortree above).
    -- FORTREE: a town in the CANOPY.  Its huts stand in the treetops and its
    -- rope walkways cross between them, both at elevation 4, over trees at 3
    -- -- which is why `course` is 32 here rather than 16: "one course of
    -- separation would put the walkway INSIDE the canopy it is supposed to
    -- cross".
    --
    -- `canopy_walk` says the same thing to the tree builder.  A wood's crown
    -- is stacked two cells tall (see `buildCylinders`), which is right where
    -- the only thing above a tree is sky and wrong here: doubling Fortree's
    -- canopy swallowed the walkways and the huts standing in it -- 362 of its
    -- cells, reported as "the bridges in Fortree have been turning into
    -- cylinders" and "some trees aren't the right height, they're supposed to
    -- sit below the huts".
    --
    -- Where the town is IN the canopy, the canopy is one cell tall and the
    -- things built in it sit above it.
    FortreeCity = { course = 32, canopy_walk = true },

    -- Route 110's cycling road: 592 bridge cells at ELEVATION_MULTI_LEVEL
    -- over 1242 ocean cells at the surf level -- the clearest case in the
    -- game of two walkable surfaces stacked in Z on the same XY, and the
    -- reason the bridge lift is measured from the DATUM rather than from the
    -- water underneath it.
    -- ...and its ELEVATION FIELD IS TRAFFIC CONTROL, not terrain: two land
    -- levels stated, no cliff drawn anywhere on the route.  `causeway`
    -- keeps the land on the datum and gives every bridge-behaviour cell its
    -- full lift over it, so the road flies over a flat coastal plain the
    -- way the drawing shows it -- and the crossings sit flush with the
    -- causeway they continue instead of hovering a storey above it.
    Route110 = { causeway = true },

    -- Route 120: a low bridge in the south and a high one in the north over
    -- one pond, which is exactly what bridge_lift exists to tell apart.
    Route120 = {},

    -- Mossdeep: seven distinct levels (0,1,3,4,5,7,9), the richest elevation
    -- set of any town and the best test of the ranking rule -- read as raw
    -- course counts it would be a 96px cliff where the art draws four.
    MossdeepCity = {},

  },
}
