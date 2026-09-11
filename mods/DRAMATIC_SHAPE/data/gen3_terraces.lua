-- GEN 3 TERRACE HEIGHTS -- the sculpted answer, one line per terrace.
--
-- WHY THIS FILE EXISTS.
--
-- Every height model tried before this one INFERS the relief from the art at
-- render time, and each inference has a map it cannot read.  The band raster
-- (`Structures.gen3BandLevels`) gets the terraces themselves right -- measured:
-- every walkable component in Sootopolis, Rustboro, Route 123 and Mt Chimney
-- lies inside a single band, so the modal vote that picks a component's level
-- is exact -- and then the relaxation that runs after it moves 33 of
-- Sootopolis' 80 terraces back off their band, and 23% of the map's tiles end
-- up drawn at a height the pass did not ask for.
--
-- Chasing that with more inference has been tried from four directions and the
-- rejected experiments are all recorded in HOENN_RELIEF/NOTES.md.  So the
-- terrace heights stop being inferred and become DATA: a number per terrace,
-- readable against the 2D map, which no later pass may overrule.
--
-- THIS IS NOT A `map.id` SPECIAL CASE.  There is no branch anywhere that names
-- a map; there is one uniform lookup, by the cartridge's own map name, into
-- this table.  A map absent from it keeps the inferred path exactly as before,
-- which is what keeps Gen 1, Gen 2 and Prism untouched.
--
-- THE FORMAT.
--
--   ["MapName"] = { { anchorX, anchorY, level }, ... }
--
-- A terrace is named by its ANCHOR: the first cell of its walkable component
-- in reading order (top row first, then left to right).  The loader re-floods
-- the component from that cell rather than storing every cell, so the file
-- stays hand-editable -- Sootopolis is eighty lines, not 3,600.
--
-- `level` is in COURSES above the water, the same unit the band map draws and
-- the same one a person counts off the 2D map: 0 is the sea, and each terrace
-- edge or stair tile you cross on the way up is one more.
--
-- SEEDED FROM THE BAND RASTER, because the raster is already right for most
-- terraces; the hand pass is corrections, not a blank page.  A line that has
-- been checked against the drawing carries `-- ok`; one that has been changed
-- carries the reason.
--
-- THE SEED RULE IS ONE COURSE PER RUN OF THE SAME EDGE METATILE -- what the
-- raster calls MODE=run.  One course per edge CELL was tried first, because
-- "each stair tile for cliff edge or cliff face should raise the height by 1"
-- reads that way and it is the rule that reaches thirteen in Sootopolis.  The
-- frame says no: every boundary in the town becomes a wall several courses
-- tall, the cliff drawing fills in between, and the city renders as a maze of
-- white rock with the houses sunk into it.
--
-- Thirteen is the DEPTH of the drop from rim to lake, not the number of places
-- to stand.  There are seven of those.  The rest of the height belongs to how
-- deep each cliff is drawn between two terraces, which is a question about the
-- wall, not about this table.
--
-- ...AND IT IS READ WITH THE PAVING DEMOTED.
--
-- Sootopolis' pale stone is metatile 729, drawn with a lit top edge and a
-- shadow -- the same way the tileset draws a terrace rim -- so the reader
-- called all 894 of its cells a step.  607 of them are walkable, and you
-- cannot stand on the front of a cliff.  `Gen3.isGroundMeta` demotes a
-- metatile that is walkable in most of the places it appears; see the census
-- on that function.  Seeded before that landed, this table was a rainbow.
--
-- ...AND THE DATUM IS THE CARTRIDGE'S WATER, NOT THE ART'S.
--
-- `Gen3.roleAt` called the Pokemon Mart's blue roof water, so the flood was
-- seeded at zero in the middle of the town and everything around it was
-- dragged down -- the sunken-behind-the-Mart report, traced to a cheapest path
-- that began inside the building.  The seed reads the behaviour byte instead.
-- With that and the shore step, the west column at x=12 reads 1, 2, 3 against
-- the art's 1, 2, 3 where it used to read 0, 0, 1.
--
-- THE SHORE IS THE DATUM.  The grass beside the lake is ground level and the
-- lake is dug out of it, so Sootopolis' eight walkable heights are 0 through 7
-- -- eight distinct levels, which is the eight counted off the 2D map.
--
-- ...AND THE HEIGHT IS WHAT THE STAIRCASES SAY.
--
-- In a town you cannot walk up a cliff, so a terrace is as high as the number
-- of FLIGHTS climbed to reach it from the shore.  Calibrated against the count
-- off the 2D map: Sootopolis is eight high in walkable terraces, and this rule
-- gives exactly eight.  One contiguous flight is one course however deep it is
-- drawn; stacked flights separated by a landing stack.  The constraint runs
-- both ways, so a flight coming DOWN from a terrace already fixed pulls the
-- ground south of it one lower.  See `Structures.gen3BandLevels`.
--
-- (superseded, kept for the record:)
-- ...AND THE WALK PAYS ONCE PER WALL WITH NO ROAD ALONG IT.
--
-- Charging per run of the same edge metatile made the rock network a free
-- highway: traced to (12,17), the flood paid one to enter the wall at (23,23)
-- and ran six cells along the inside of it for nothing, undoing two staircases
-- on the way.  The walk now carries a heading -- free to turn on ground, one
-- course to enter rock and the heading locks, straight on only inside it.  See
-- `Structures.gen3BandLevels`.
--
-- ONLY THE MAPS THE STAIRCASES CAN SPEAK ABOUT ARE IN HERE.
--
-- The rule derives height from the only way a player may climb, so a map with
-- no flight joining two terraces gets no entry and keeps the passes it had
-- before.  Towns draw staircases; routes and mountains draw CLIFFS, which is a
-- different statement.  Measured across the region, `banded` walkable art
-- outside a town tileset is almost absent -- Mt Pyre and Lavaridge have none
-- at all, Route 112 and Mt Chimney two cells each.
--
-- Answering anyway is what a first run did, and it flattened Hoenn: 80 maps at
-- one course with Sootopolis the only relief on the cartridge.
--
-- THE MERGE IS GONE.  It existed to smooth a raster that was noisy cell by
-- cell; the staircase model has no such noise -- a terrace takes one number
-- because a terrace is one piece of ground -- and the median it took differed
-- from the component's own reading on 3 of Sootopolis' 80 terraces, which is
-- 3 terraces of smoothing with nothing to smooth.
--
-- (superseded, kept for the record:)
-- ...AND THE SEED IS MERGED ACROSS EVERYTHING THAT IS NOT A WALL.
--
-- The raster is noisy cell by cell -- a wall is one metatile per course, and
-- which course a path is charged depends on the direction it comes from -- so
-- eighty scraps of Sootopolis floor, each voting its own band, come out a
-- course apart from their own neighbours.  A railing is not a terrace edge.
-- The seed therefore unions components through rails, planters, signposts,
-- trees and the ground under houses, cutting only at walls and staircases, and
-- gives each union the MEDIAN band of its cells, which the noise cannot move
-- the way it moves a mode.
return {
  version = 1,
  maps = {
    -- FortreeCity  40x20  13 terrace(s), tallest band 1
    ["FortreeCity"] = {
      { 32, 2, 1 },  -- 1 cell(s)
      { 10, 3, 1 },  -- 1 cell(s)
      { 17, 3, 1 },  -- 1 cell(s)
      { 25, 3, 1 },  -- 1 cell(s)
      { 12, 4, 0 },  -- 4 cell(s)
      { 19, 4, 0 },  -- 5 cell(s)
      { 27, 4, 0 },  -- 4 cell(s)
      { 10, 5, 0 },  -- 95 cell(s)
      { 25, 5, 0 },  -- 117 cell(s)
      { 13, 8, 0 },  -- 1 cell(s)
      { 29, 8, 0 },  -- 1 cell(s)
      { 12, 13, 1 },  -- 1 cell(s)
      { 37, 13, 1 },  -- 1 cell(s)
    },
    -- SootopolisCity  60x60  80 terrace(s), tallest band 7
    -- ROUTE 112  40x60  31 terrace(s).  Mt Chimney's foothills: the ash
    -- plateau, the Cable Car Station on it, the two Fiery Path mouths in its
    -- west wall, and the grass at its foot.
    --
    -- ONE FLIGHT, SO TWO LEVELS.  The route draws exactly one staircase --
    -- the General tileset's 175/207, six cells at (20..21, 41..43), climbing
    -- NORTH off the grass and through the rock wall onto the plateau -- and
    -- there is no other way up, because everything else round the plateau is
    -- drawn as a face you cannot climb.  A terrace is as high as the number
    -- of flights climbed to reach it, so the plateau is 1 and the land at its
    -- foot is 0.  Nothing here is eyeballed off the picture.
    --
    -- AND THE CARTRIDGE SORTS THE THIRTY-ONE TERRACES ITSELF.  Emerald marks
    -- the plateau MB_MOUNTAIN_TOP (0x0C) and the low ground MB_NORMAL, and
    -- the split is total:
    --
    --   19 terraces, 173 cells   MOUNTAIN_TOP on every cell   -> 3
    --   12 terraces, 355 cells   MOUNTAIN_TOP on none of them -> 0
    --
    -- ...AND THE NUMBER IS THREE, NOT ONE, BECAUSE THE CLIFF IS DRAWN THREE
    -- DEEP.  One flight = one course is the rule for a TOWN, where a
    -- staircase is a step between two paved levels.  A route draws its drop
    -- instead: between the plateau's last walkable ash at row 40 and the
    -- grass at row 44 the art puts THREE rows of cliff -- 41, 42, 43 -- and
    -- the staircase through it is three stacked stair metatiles, 175/207 at
    -- each of those rows.  Reported from the frame: "the terrace with 3
    -- stacked cliffs and 3 stacked stairs is only 1 high".  It is three, and
    -- the flight ramps 48px over its three cells.
    --
    -- (terrace `m`, the plateau's 128-cell main floor, reads 125 of 128; the
    -- three are the Cable Car Station's own doorstep.)  So the numbers below
    -- are the behaviour byte, not a reading of the art -- the art was used
    -- only to check the answer, and it agrees: green grass at the bottom and
    -- along the east, ash above the rock wall.
    --
    -- The nineteen one-cell terraces are gaps in the tree lines and pockets
    -- in the lava ridges; they are cut out as their own components because a
    -- ledge or a tree separates them, and each takes the level of the ground
    -- it is drawn on.
    ["Route112"] = {
      { 26,  6, 0 },  -- 91 cell(s)   the north grass, below the plateau's north face
      { 23, 19, 3 },  -- 2 cell(s)
      { 21, 20, 3 },  -- 1 cell(s)
      { 20, 21, 3 },  -- 5 cell(s)
      { 22, 21, 3 },  -- 1 cell(s)
      { 24, 22, 3 },  -- 1 cell(s)
      { 30, 22, 3 },  -- 7 cell(s)
      { 22, 23, 3 },  -- 20 cell(s)
      { 34, 23, 3 },  -- 1 cell(s)
      { 33, 25, 3 },  -- 1 cell(s)
      { 11, 26, 3 },  -- 1 cell(s)   a pocket in the west lava mass
      { 21, 27, 3 },  -- 1 cell(s)
      { 28, 27, 3 },  -- 128 cell(s) the ash plateau's main floor
      { 22, 28, 3 },  -- 1 cell(s)
      { 19, 29, 3 },  -- 1 cell(s)
      { 34, 29, 3 },  -- 1 cell(s)
      { 16, 30, 3 },  -- 2 cell(s)
      { 35, 31, 3 },  -- 1 cell(s)
      { 34, 33, 3 },  -- 1 cell(s)
      { 15, 34, 3 },  -- 1 cell(s)
      { 35, 35, 0 },  -- 1 cell(s)   east grass strip, outside the plateau wall
      { 34, 36, 0 },  -- 1 cell(s)
      { 35, 41, 0 },  -- 1 cell(s)
      { 31, 42, 0 },  -- 1 cell(s)
      { 14, 43, 0 },  -- 10 cell(s)  a grass corridor between two lava ridges
      { 26, 43, 0 },  -- 164 cell(s) the south grass, the staircase's bottom
      { 36, 43, 0 },  -- 1 cell(s)
      { 16, 44, 0 },  -- 9 cell(s)
      {  6, 46, 0 },  -- 66 cell(s)  the south-west grass
      { 11, 46, 0 },  -- 14 cell(s)
      { 18, 54, 0 },  -- 6 cell(s)
    },

    ["SootopolisCity"] = {
      { 16, 0, 6 },  -- 1 cell(s)
      { 18, 0, 6 },  -- 10 cell(s)
      { 39, 0, 5 },  -- 5 cell(s)
      { 55, 0, 4 },  -- 7 cell(s)
      { 13, 2, 6 },  -- 3 cell(s)
      { 34, 2, 5 },  -- 5 cell(s)
      { 43, 2, 5 },  -- 20 cell(s)
      { 25, 3, 5 },  -- 45 cell(s)
      { 38, 3, 5 },  -- 4 cell(s)
      { 7, 5, 7 },  -- 3 cell(s)
      { 15, 5, 6 },  -- 25 cell(s)
      { 37, 5, 5 },  -- 6 cell(s)
      { 41, 5, 5 },  -- 6 cell(s)
      { 57, 5, 4 },  -- 7 cell(s)
      { 47, 6, 5 },  -- 1 cell(s)
      { 9, 7, 7 },  -- 1 cell(s)
      { 5, 8, 7 },  -- 2 cell(s)
      { 43, 8, 5 },  -- 4 cell(s)
      { 7, 9, 6 },  -- 2 cell(s)
      { 27, 9, 4 },  -- 9 cell(s)
      { 19, 10, 5 },  -- 2 cell(s)
      { 40, 11, 4 },  -- 1 cell(s)
      { 45, 11, 4 },  -- 31 cell(s)
      { 56, 11, 4 },  -- 4 cell(s)
      { 59, 11, 4 },  -- 1 cell(s)
      { 0, 12, 5 },  -- 2 cell(s)
      { 10, 12, 5 },  -- 9 cell(s)
      { 23, 12, 3 },  -- 1 cell(s)
      { 37, 12, 3 },  -- 1 cell(s)
      { 3, 13, 5 },  -- 7 cell(s)
      { 18, 13, 4 },  -- 1 cell(s)
      { 25, 13, 3 },  -- 13 cell(s)
      { 53, 13, 4 },  -- 12 cell(s)
      { 58, 13, 4 },  -- 2 cell(s)
      { 5, 14, 4 },  -- 10 cell(s)
      { 12, 14, 4 },  -- 32 cell(s)
      { 19, 15, 4 },  -- 2 cell(s)
      { 22, 15, 2 },  -- 3 cell(s)
      { 36, 15, 3 },  -- 2 cell(s)
      { 24, 16, 2 },  -- 10 cell(s)
      { 31, 16, 1 },  -- 50 cell(s)
      { 39, 16, 3 },  -- 1 cell(s)
      { 42, 16, 3 },  -- 26 cell(s)
      { 35, 17, 1 },  -- 9 cell(s)
      { 16, 18, 3 },  -- 16 cell(s)
      { 47, 18, 3 },  -- 1 cell(s)
      { 59, 18, 4 },  -- 3 cell(s)
      { 7, 21, 3 },  -- 1 cell(s)
      { 52, 21, 3 },  -- 3 cell(s)
      { 9, 22, 3 },  -- 6 cell(s)
      { 20, 22, 2 },  -- 6 cell(s)
      { 55, 22, 2 },  -- 24 cell(s)
      { 5, 23, 2 },  -- 9 cell(s)
      { 44, 23, 2 },  -- 41 cell(s)
      { 51, 23, 3 },  -- 8 cell(s)
      { 12, 24, 2 },  -- 14 cell(s)
      { 0, 25, 2 },  -- 3 cell(s)
      { 18, 25, 1 },  -- 2 cell(s)
      { 21, 25, 1 },  -- 29 cell(s)
      { 55, 26, 2 },  -- 9 cell(s)
      { 0, 29, 2 },  -- 4 cell(s)
      { 3, 30, 2 },  -- 11 cell(s)
      { 7, 30, 2 },  -- 8 cell(s)
      { 15, 30, 2 },  -- 41 cell(s)
      { 27, 32, 0 },  -- 36 cell(s)
      { 42, 32, 1 },  -- 32 cell(s)
      { 54, 32, 2 },  -- 3 cell(s)
      { 58, 32, 1 },  -- 4 cell(s)
      { 4, 34, 2 },  -- 1 cell(s)
      { 53, 34, 1 },  -- 3 cell(s)
      { 15, 35, 1 },  -- 3 cell(s)
      { 2, 36, 2 },  -- 2 cell(s)
      { 5, 36, 2 },  -- 2 cell(s)
      { 19, 36, 0 },  -- 8 cell(s)
      { 40, 37, 0 },  -- 48 cell(s)
      { 57, 37, 1 },  -- 1 cell(s)
      { 0, 38, 0 },  -- 1 cell(s)
      { 2, 38, 0 },  -- 9 cell(s)
      { 17, 38, 0 },  -- 62 cell(s)
      { 50, 48, 0 },  -- 4 cell(s)
    },
  },
}
