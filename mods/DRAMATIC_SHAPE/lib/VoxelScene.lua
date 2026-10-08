-- Voxel world mode: assemble and draw one frame of the 3D scene.
--
-- World space is world pixels and shares its origin with the 2D paths, so
-- the terrain mesh needs no transform at all and a connected map just
-- translates by the same (ox, oy) the flat renderer already offsets it by.
--
-- Order is: the sun's shadow pass, then terrain, then characters, then a 2D
-- overlay for the field FX. There is no y-sort anywhere -- the depth buffer
-- resolves occlusion, which is the whole point of the mode. Walk behind a
-- building and the building is simply in front.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Perf = V.require("Perf")
-- The PERFORMANCE tier's ceilings (lib/Tier.lua). Top-level here rather
-- than lazily as in ShadowMap/Water/AntiAlias: Tier requires nothing from
-- this mod, so there is no load order to protect, and the sun's rate
-- limiter reads it once per stale frame.
local Tier = V.require("Tier")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")
local ChunkMesher = V.require("ChunkMesher")
local SpriteBillboards = V.require("SpriteBillboards")
local TileShape = V.require("TileShape")
local Structures = V.require("Structures")
local TerrainAtlas = V.require("TerrainAtlas")
local Voxel = V.require("VoxelState")
local Sky = V.require("Sky")
local Water = V.require("Water")
local Gen3 = V.require("Gen3")
local VoxelGrid = V.require("VoxelGrid")
local DayNight = V.require("DayNight")
local FirstPerson = V.require("FirstPerson")
local BattleBillboard = V.require("BattleBillboard")
local Pokedex = V.require("Pokedex")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.Map")

local VoxelScene = {}

-- What the active display mode actually paints with.
--
-- paletteFor hands back a map's RAW SGB zone palette, and that is not what
-- any of the non-colour modes draw. The flat path runs it through
-- PaletteFX.effectiveColors on the way to the shade-remap shader, and that
-- call IS where GRAY, INVERTED and CLASSIC happen -- OG / OG INV replace
-- the palette with the DMG greys (inverted for the latter), CLASSIC
-- replaces it with the green DMG set, and GBC INV permutes the zone's own
-- shades. GBC and RED++ pass through untouched.
--
-- This pass has no shader to apply that in: colour is baked into the atlas
-- and into the sprite sheets ahead of the draw, so it has to run the same
-- transform itself. Without it every mode that is not already a colour mode
-- comes through wearing the SGB palette -- grey and inverted both rendering
-- as plain SGB blue.
local function modeColors(paletteFor, map)
  local c = paletteFor and paletteFor(map) or nil
  return PaletteFX.effectiveColors(c)
end

VoxelScene._modeColors = modeColors   -- named for the suite

-- ------------------------------------------------------------------ sky --
--
-- The void behind the diorama is SKY, at every rung -- so the world reads as
-- standing under something rather than floating on a black plate.
--
-- What is up there differs by rung, and the sky follows it rather than being
-- retuned for each. At 75 degrees the camera is pitched far enough over that
-- the horizon is genuinely in frame, and the bands run down to meet it. At the
-- steeper rungs the horizon is above the top edge and the void that shows is
-- where the ground runs OUT -- past the map edge, past the curve -- so the
-- bands take a fixed slice of the frame instead (lib/Sky.lua, Sky.SPAN) and the
-- haze below them fills the rest.
--
-- INDOORS THERE IS NO SKY. A house, a cave or a gym is a room with a
-- ceiling, and the void past its walls is the outside of a box, not open
-- air. Map.isOutdoor is the same test the engine uses for door SFX and the
-- town map, and the same one Structures already asks to decide whether a
-- map rings with trees.
--
-- The colour is a four-shade ramp shaped like a world palette so the
-- display mode can transform it exactly like one: GRAY gets a grey sky,
-- CLASSIC a green one, GBC INV a dark one, and the colour modes the blue.
-- A hardcoded blue would sit wrong in every non-colour mode -- the same
-- mismatch the terrain bake had.
--
-- This ramp is the FLAT sky -- what a caller clears the void to. The free-roam
-- camera's banded sky has a palette of its own (lib/Sky.lua), transformed the
-- same way by the same seam; they are separate because the flat one also has to
-- serve an indoor void and a battle's arena, which want a colour rather than a
-- sky.
local SKY_SHADES = { { 222, 242, 255 }, { 135, 196, 240 },
                     { 64, 120, 192 }, { 16, 40, 80 } }
local SKY_SHADE = 2       -- the ramp's "sky" proper; 1 is its highlight

-- the ramp as the display mode has it, which is the only form anything here
-- should be reading it in
local function skyRamp()
  return PaletteFX.effectiveColors(SKY_SHADES) or SKY_SHADES
end

-- Full strength at every rung: the sky is painted wherever the diorama is.
--
-- The ramp that is left is for ARRIVAL alone. Switching the mode on eases the
-- camera up from flat, and the sky comes up with it over the first few degrees
-- rather than appearing whole on the keypress -- which is also what keeps a
-- top-down camera, where there is no void worth speaking of, from painting one.
local SKY_FADE_DEG = 8

local function skyStrength(angleRad)
  local deg = math.deg(angleRad or 0)
  if deg <= 0 then return 0 end
  local t = deg / SKY_FADE_DEG
  return t < 1 and t or 1
end

-- One shade off the sky ramp, transformed by the display mode, as an
-- {r, g, b, a} in 0..1. `shade` picks the rung (SKY_SHADE is the sky
-- proper; 4 is its darkest, which is what an indoor void wants).
function VoxelScene.skyShade(shade, alpha)
  local shades = skyRamp()
  local c = shades[shade] or SKY_SHADES[shade] or SKY_SHADES[SKY_SHADE]
  return { c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1 }
end

-- The sky `map` stands under at strength `t`, or nil where there is no sky
-- to paint: indoors, or with the horizon out of frame.
--
-- One flat colour, which is what a caller that only needs something to clear the
-- void to wants -- the overworld battle's arena shot is one of those. The
-- gradient is added on top of this by skyFor, for the free-roam camera alone.
function VoxelScene.skyColor(map, t)
  if not (map and map.def and Map.isOutdoor(map.def)) then return nil end
  if not t or t <= 0 then return nil end
  local sky = VoxelScene.skyShade(SKY_SHADE, t)
  -- outdoors the flat fill follows the CLOCK: it becomes the hour's haze --
  -- gold at dusk, navy at night -- so a battle staged on the map at
  -- midnight is under a midnight void, not a noon one. Free-roam is
  -- unchanged by this: Sky.dress overwrites the fill with the same value.
  local haze = Sky.haze()
  if haze then sky[1], sky[2], sky[3] = haze[1], haze[2], haze[3] end
  return sky
end

-- The free-roam sky: the flat one above, dressed with the banded gradient
-- (lib/Sky.lua).
--
-- Only here, and deliberately. This is the sky the walking camera stands under,
-- where the horizon is a quarter of the way down the frame at the top rung and
-- one flat blue reads as a wall of paint. A battle is a staged shot with its own
-- placed camera whose horizon sits above the frame entirely, so it keeps the
-- flat fill it has always had -- there is no gradient to see from down there,
-- and the arena's look is not this rung's to change.
local function skyFor(map)
  local sky = VoxelScene.skyColor(map, skyStrength(Voxel.angle))
  if not sky then return nil end
  -- DIAGNOSTIC ONLY -- see HOENN_RELIEF/tools/sky_holes.py.  Emerald's water
  -- renders the sky's own colour, so a hole and a pond are the same pixel and
  -- no screen-reading metric can tell them apart.  Painted flat magenta this
  -- shot answers the question outright.  Never shipped.
  if os.getenv("POKEPORT_SKY_FLAT") then
    return { 1, 0, 1, 1 }
  end
  return Sky.dress(sky)
end

VoxelScene._skyFor = skyFor           -- named for the suite
VoxelScene._skyStrength = skyStrength

-- A facing as a yaw about +Y, kept for callers that reason about which way
-- an entity points (the mod exports it). The character cards themselves
-- never yaw -- they face south and lean, like the flat game.
local YAW = {
  down = 0,
  up = math.pi,
  right = math.pi / 2,
  left = -math.pi / 2,
}

-- The ground height a cell stands at, so a character on a ledge stands on
-- top of it rather than sunk into it. Uses the same bottom-left collision
-- tile the engine walks on (Map:cellTile).
-- `px`/`py` are the entity's WORLD PIXEL position, when the caller has one.
-- They are what makes a flight climb continuously instead of in cell-sized
-- jerks: without them a stair cell can only answer one height for the whole
-- cell, and the walker pops.  Optional, because plenty of callers ask about a
-- cell with nobody standing in it.
local function groundAt(map, cellX, cellY, elev, px, py)
  -- Off the map, cellTile border-extends into the map's borderBlock --
  -- which on maps ringed with trees is a RAISED tile. The only entity
  -- ever standing off-map is the player mid seam-step (placed one cell
  -- before the connection entry), and the ground actually rendered
  -- there is the departed neighbour's flat walkway: height 0. Without
  -- this, crossing into such a map hoisted the walker tree-high for
  -- exactly one step -- the "hops like a ledge" seam bug.
  if not map:inBounds(cellX, cellY) then return 0 end
  local shapes = TileShape.forMap(map)
  -- the same full resolution the mesher draws with, NOT the raw tile table:
  -- on Gen 2 map:cellTile answers a COLLISION CLASS rather than a tile id,
  -- so indexing the tile shapes with it read some unrelated tile's box and
  -- stood every character 16px above the ground they were walking on
  local tx, ty = cellX * 2, cellY * 2 + 1
  local s = TileShape.at(map, shapes, Gen3.tileAt(map, tx, ty), tx, ty)
  if not s then return 0 end
  -- A WATERFALL IS A CLIMB, NOT A DOORWAY.
  --
  -- REPORTED from play: "when on the waterfall it has me float above the
  -- water and below the map as well instead of climbing the waterfall
  -- vertically tile by tile to the peak of it".
  --
  -- A fall's cells are WALKABLE -- that is what lets you ride one -- and
  -- their art is `upright`, so every one of them fell into the doorway arm
  -- below and was answered `standHeight`: the rock beside the sheet where
  -- there is any, and the world datum where there is none.  Measured at
  -- MeteorFalls_1F_1R (8..15, 10..14), sheet at 172 over a pool at 92:
  -- 224 on the top row and nil -> 0 on the bottom two.  Above the water at
  -- one end, under the map at the other, which is the report exactly.
  --
  -- The sheet itself is plumb and stays plumb -- `Structures`' fall pass
  -- argues that at length, and a graded one reads as a weir.  Riding it is
  -- the other question: the rider leaves the lower pool at its surface,
  -- arrives at the upper one at the crest, and the drawn rows between
  -- spread the drop evenly, so a five-row fall over eighty pixels is five
  -- sixteen-pixel steps -- one per drawn row, which is what "tile by tile"
  -- asks for.  `py` makes it continuous within each row, the same way the
  -- flight arm below uses it, so the climb is a ramp rather than a stair
  -- of teleports.
  --
  -- Asked BEFORE the doorway arm because a fall satisfies that arm's test
  -- and would never reach here otherwise.  A fall with a pool at only one
  -- end states no climb, answers nil, and keeps the behaviour it had.
  if s.class == "waterfall" and Structures.fallRide then
    local okF, foot, crest, minY, maxY =
      pcall(Structures.fallRide, map, cellX, cellY)
    if okF and foot and crest and maxY and minY and crest > foot then
      local n = maxY - minY + 1
      if n > 0 then
        -- 0 at the cell's NORTH edge, 1 at its south: py grows southward
        local sub = 0.5
        if py then
          sub = (py % 16) / 16
          if sub < 0 then sub = 0 elseif sub > 1 then sub = 1 end
        end
        -- northward progress up the sheet: 0 where the bottom row meets
        -- the pool, 1 where the top row meets the river
        local u = ((maxY - cellY) + (1 - sub)) / n
        if u < 0 then u = 0 elseif u > 1 then u = 1 end
        return foot + (crest - foot) * u
      end
    end
    -- ...AND A FALL THE OTHER PASS BUILT RIDES ON ITS OWN SHEET.
    --
    -- `Structures.buildFalls` -- the pass that serves every map without a
    -- stated pool at both ends -- grades a fall row by row already: "a
    -- stair of water losing one course a row, crest at the top, river
    -- level at the foot", written into the run.  EVER GRANDE CITY is the
    -- whole of that case and it is the waterfall the game makes you climb:
    -- 96 cells over eight rows, runs stepping 90, 78, 66 and down, and
    -- `standHeight` answered nil on every one of them, so the rider sat at
    -- the datum under ninety pixels of water.
    --
    -- The run IS the surface there, so ride it.  Asked second because a
    -- stated climb between two pools is the better answer where there is
    -- one, and `runHeight` says nothing on the maps that have it.
    local sheet = Structures.runHeight(map, tx, ty)
    if sheet and sheet > 0 then return sheet end
  end
  -- a box the walker passes THROUGH rather than onto: Gen 2 pins its
  -- doorways solid so the facade closes over them, and the cell they are
  -- cut into stays walkable
  if s.art == "upright" and map:isWalkableCell(cellX, cellY) then
    -- ...but at the height that box STANDS ON, not at the world datum.
    -- A Sootopolis doorway is cut into a facade founded four courses up,
    -- and answering 0 here walked the player out of the house and into
    -- the inside of the terrace below it.
    return Structures.standHeight(map, tx, ty) or 0
  end
  -- a recessed class (water) still supports whatever stands on it; only
  -- raised ground lifts the model.  Stairs never do: the class height is
  -- the flight's TALL end, but the player enters at floor level and the
  -- warp fires as they step in -- lifting them onto the geometry read as
  -- climbing an invisible block
  -- `s` is the TILE's own shape, and Gen 3 has no stair art in the tileset:
  -- its flights are found by Structures, from tread art and the profile's
  -- flight lists, and marked on the cell.  Ask there too or the branch below
  -- can never fire on a Hoenn map.
  local marked = false
  if Structures.stairAt then
    local okS, m2 = pcall(Structures.stairAt, map, tx, ty)
    marked = (okS and m2) or false
  end
  if s.art == "stair" or marked then
    -- A FLIGHT CLIMBS.
    --
    -- This used to answer `standHeight` -- the flight's FOOT -- so walking a
    -- staircase never raised the walker at all: they slid along the bottom
    -- terrace with the treads drawn under their feet, arrived at the top and
    -- popped up a course.  That is the whole of the "stairs don't lead up to
    -- the next level" report.
    --
    -- The flight's two LANDINGS give the gap, through the same ranked
    -- elevation table the terraces are built from, so the top tread and the
    -- terrace it serves are equal by construction.  Position along the run
    -- gives the rest: a multi-cell flight spreads one rise over all its
    -- cells rather than a course per tile.
    local z0, z1, axis, heading, idx, n = Structures.flightEnds(map, cellX, cellY)
    if z0 and z1 and n and n > 0 then
      local sub = 0.5
      if px and py then
        local off = (axis == "x") and (px % 16) or (py % 16)
        sub = off / 16
        if sub < 0 then sub = 0 elseif sub > 1 then sub = 1 end
      end
      -- WHICH TREAD IS THE BOTTOM ONE -- and the collision had it backwards
      -- while the MESH had it right, which is why the stairs looked correct
      -- and walked inverted: "the bottom stair raises me up to the height of
      -- the highest stair and the highest stair lowers me to the height of
      -- the lowest".
      --
      -- `flightEnds` returns its two landings SORTED -- z0 is the low one --
      -- but `idx` counts from the run's START, which is the high end whenever
      -- `heading` is -1.  Flipping only `sub` reverses the ramp WITHIN each
      -- tread and leaves the tread order alone, so the whole flight ran the
      -- wrong way round.
      --
      -- `ChunkMesher`'s tread pass already states the rule -- "the index from
      -- the LOW end is one or the other" -- so use the same expression here
      -- and the two agree by construction instead of by correction.
      local fromLow = (heading == 1) and idx or (n - 1 - idx)
      if fromLow < 0 then fromLow = 0 end
      if heading and heading < 0 then sub = 1 - sub end
      local t = (fromLow + sub) / n
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      return z0 + (z1 - z0) * t
    end
    -- NOTHING TO CLIMB BETWEEN.  A flight with one landing, or two at the
    -- same level, still stands on a terrace -- and `standHeight` answers the
    -- LOWEST walkable neighbour, which beside a ring at 48 is the lake.  Ask
    -- the terrace pass for the foot it gave this run before falling back to
    -- a reading of the neighbourhood.
    if Structures.terraceAt then
      local okT, tz = pcall(Structures.terraceAt, map, cellX, cellY)
      if okT and type(tz) == "number" then return tz end
    end
    return Structures.standHeight(map, tx, ty) or 0
  end
  -- THE TERRACE IS THE FLOOR, WHATEVER THE CELL'S ART BECAME.
  --
  -- Structures.finishedFloor -- which every height pass in that file is built
  -- on -- reads S.synthZ FIRST and only then looks at the cell's shape.  This
  -- function did the opposite, so the two disagreed about the same cell: at
  -- Mt Chimney (14..16, 37) three walkable cells of one flat corridor all
  -- carried synthZ 80, and because the volume pass had left a "wall" shape on
  -- two of them, groundAt answered 32, 0 and 80 along a row you can walk in a
  -- straight line.  That is the verticality glitch, and it is a disagreement
  -- between two files rather than a wrong height in either.
  --
  -- ...and a cell the mesher gave a MEASURED height to answers with that
  -- one, not with its class default: the river above a waterfall is drawn
  -- at the fall's crest (Structures.buildFalls), and a surfer reading the
  -- class height alone swam four cells under the sheet he was floating on.
  -- A BRIDGE CELL IS TWO PLACES, and the walker's ELEVATION says which.
  --
  -- Emerald's MULTI cells keep the elevation you arrived with -- that is
  -- the whole mechanism of walking UNDER the cycling road while someone
  -- rides over your head.  The deck height is right only for the walker
  -- who is ON the deck; answered to the one underneath it teleported them
  -- onto the road the moment they stepped into its shadow.  The engine
  -- tracks the elevation per entity exactly as the cartridge does, so ask
  -- it: an entity below the bridge's own level stands on the ground the
  -- bridge spans.
  -- A DECK IS THE FLOOR ONLY FOR WHOEVER IS ON IT.
  --
  -- Keyed on the cartridge's own ELEV_MULTI (15) rather than on the voxel
  -- class, because the class does not always say bridge.  Victory Road's
  -- crossings carry no bridge BEHAVIOUR at all -- they are ordinary floor
  -- metatiles whose only statement of "this is a deck" is elevation 15 --
  -- so a class test saw thirty perfectly ordinary `ground` cells and lifted
  -- every walker onto them.  That is the teleport-onto-the-bridge report.
  --
  -- THIS QUESTION IS ASKED BEFORE THE TERRACE, AND IT HAS TO BE.
  --
  -- MOTIVATED BY FORTREE CITY (30..33, 14), THE ONE SPAN IN HOENN YOU CAN
  -- WALK UNDER: four cells of MB_FORTREE_BRIDGE at ELEV_MULTI, the rope
  -- walkway at 32 crossing a street at 0.
  --
  -- The terrace short-circuit below was added for Mt Chimney's corridor and
  -- it answers `S.synthZ` for ANY walkable cell -- including a deck.  Fortree's
  -- span carries synthZ 32, so every walker there was answered 32 whatever
  -- elevation they arrived with, and the block underneath -- written for
  -- exactly this case -- could never run.  The player walking the street was
  -- lifted onto the planks over their head.
  --
  -- ...AND THE SPAN IS WALKED, NOT PEEKED AT.
  --
  -- The old search looked at the four touching cells only, and the middle of
  -- a MULTI span has MULTI on both sides and the ground it crosses on the
  -- other two: at (31,14) and (32,14) no neighbour is at the walkway's own
  -- level, so the search failed and the fallback answered the DATUM.  A
  -- walker on the deck fell 32px through it.  Measured with the map's
  -- Structures analysis dropped -- which is the state `ChunkMesher.refresh`
  -- leaves it in while the stale mesh keeps drawing, and g3-tier-224's seam
  -- refresh now does that mid-session -- FortreeCity y=14, elev 4:
  --
  --     x  ..29  30  31  32  33  34..
  --     h    32  32   0   0  32  32
  --
  -- and once `forMap` had rebuilt the cache the terrace answered 32 again.
  -- That is "the bridge where there is a path to walk under it is making me
  -- fall through but then after some time will pop me back up".
  --
  -- So walk ALONG the deck to find the level the walker is on, and where the
  -- span states nothing about that level, fall through to the ordinary
  -- reading -- the deck's own drawn height -- rather than inventing a hole.
  local okG3, g3ctx = pcall(Gen3.forMap, map)
  local cellE = nil
  if okG3 and g3ctx and g3ctx.elevationAt then
    local okE, e2 = pcall(g3ctx.elevationAt, cellX, cellY)
    cellE = okE and e2 or nil
  end
  local isDeck = (s.class == "bridge" or s.class == "log") or cellE == 15
  -- a walker whose own elevation IS this cell's is standing ON it, whatever
  -- the class says: only a walker at a DIFFERENT stated level is underneath
  if isDeck and elev ~= nil and elev ~= 0 and elev ~= 15 and cellE ~= elev
     and okG3 and g3ctx and g3ctx.elevationAt and g3ctx.groundHeight then
    local seen = { [cellY * 8192 + cellX] = true }
    local queue, qi = { { cellX, cellY } }, 1
    while qi <= #queue and qi <= 24 do
      local c = queue[qi]
      qi = qi + 1
      for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local nk = ny * 8192 + nx
        if map:inBounds(nx, ny) and not seen[nk] then
          seen[nk] = true
          local okE, ne = pcall(g3ctx.elevationAt, nx, ny)
          ne = okE and ne or nil
          if ne == elev then
            -- ...AND THE NEIGHBOUR IS ASKED THE SAME QUESTION, NOT A
            -- DIFFERENT ONE.
            --
            -- `Gen3.groundHeight` is the ELEVATION grid's answer and it is
            -- not always the finished one: on a `causeway` map it pins all
            -- land to the datum on purpose and lets the bridge behaviour
            -- carry the lift, so asking it for Route 110's cycling road
            -- returns 0 where the road is drawn at 16 -- and a cyclist
            -- crossing one of that map's 185 MULTI cells fell off the
            -- flyover.  Shoal Cave's ice bridge reads 16 against a floor
            -- drawn at 32 for the same reason.
            --
            -- The neighbour is a cell at the walker's OWN level, so it can
            -- never re-enter this branch (`cellE ~= elev` fails there) and
            -- the recursion is one deep.  Ask it what it stands on and the
            -- two sides of the span agree by construction.
            return groundAt(map, nx, ny, elev) or 0
          end
          -- keep walking, but only along the span itself
          if ne == 15 then queue[#queue + 1] = { nx, ny } end
        end
      end
    end
  end

  -- A walkable cell stands on its terrace.  Ask the terrace.
  if map:isWalkableCell(cellX, cellY) and Structures.terraceAt then
    local okT, tz = pcall(Structures.terraceAt, map, cellX, cellY)
    if okT and type(tz) == "number" then return tz end
  end

  -- A CELL WHOSE DRAWING STOOD UP IS GROUND AGAIN.  Asked after the doorway
  -- and stair branches above, which have their own right answers; this is for
  -- the props -- chimneys, lamps, barrels -- whose art was lifted into a hull
  -- and whose leftover shape still carries the height that art had.
  local stamped = Structures.stampGround(map, tx, ty)
  if stamped then return stamped end

  -- ...and a cell the mesher gave a MEASURED height to answers with that
  -- one, not with its class default: the river above a waterfall is drawn
  -- at the fall's crest (Structures.buildFalls), and a surfer reading the
  -- class height alone swam four cells under the sheet he was floating on.
  local measured = Structures.runHeight(map, tx, ty)
  if measured and measured > 0 then return measured end
  if s.h > 0 then return s.h end
  -- ...AND THE SEA IS DRAWN BELOW THE DATUM, WHICH THE LINE ABOVE THROWS
  -- AWAY.
  --
  -- MOTIVATED BY THE SEA OFF ROUTE 118, and by the seafloor under it: a
  -- surfing character floated above the water they are sitting on, and a
  -- diver walking the seabed floated above that.
  --
  -- Hoenn draws its water RECESSED into its own cell -- ChunkMesher's
  -- SEAM_DATUM comment states the same fact from the other side, "Hoenn
  -- draws the sea two pixels into its own cell" -- so a water tile's
  -- height is -2 or -4 and never positive.  Every branch above is silent
  -- for such a cell: `terraceAt` is nil (the terrace pass votes on LAND,
  -- and a sea cell is in no terrace), there is no run and no stamp, and
  -- the `> 0` test rejects the one number that IS the answer.  The cell
  -- fell through to the neighbour vote and came back with the world datum,
  -- so the rider sat 2 or 4 pixels above the sheet they are drawn on.
  --
  -- Measured over the 81 outdoor maps: 57,375 cells drawn as water on 62
  -- maps; 43,070 draw their surface at -4 and 6,945 at -2, and on every
  -- one of those the character stood exactly that far above it.  The other
  -- 7,292 are already right and are untouched -- their water is drawn AT
  -- or ABOVE the datum (Route 119's river at 28, Lilycove's harbour and
  -- Route 120's ponds at 12) and the run two lines above answers them.
  --
  -- Gen 3 only.  Gen 1 and Gen 2 draw a recessed water class of their own
  -- and this is the one function every surfing character in the project
  -- asks, so the negative half of the answer is taken only where it was
  -- measured: a Kanto or Johto lake answers exactly what it always did.
  if s.class == "water" and Gen3.mapIsGen3(map) then return s.h end
  -- ...AND THE DATUM IS NOT THE DEFAULT FLOOR.
  --
  -- A walkable cell with no run and no height of its own still sits on
  -- whatever floor is around it, and answering 0 assumed that floor was the
  -- world datum.  Mt Chimney's cable car forecourt is a terrace at 32 with a
  -- bush standing on it; the bush's own cell carries no run, so it answered
  -- 0 while both its neighbours answered 32 -- a 32px hole either side of one
  -- cell, in the middle of a plaza.
  --
  -- `standHeight` is the same question a doorway and a stamp already ask:
  -- what floor is this cut into.  Only walkable cells ask it -- a blocked
  -- cell's height is its own business.
  --
  -- `standHeight` is NOT the right question here, though it is the obvious
  -- one: its ring reaches three cells and on open routes that is far enough
  -- to find some unrelated rise and drag the cell up to it.  Tried, and it
  -- fixed Mt Chimney and Sootopolis at the cost of eight new steps on Route
  -- 115 and three on Route 120 -- a net loss.
  --
  -- The conservative form is the one that holds: only the four cells
  -- TOUCHING this one vote, only walkable floor among them, and only when
  -- they AGREE.  A bush standing in a plaza has terrace on every side and
  -- takes it; a cell on open ground has neighbours that differ, or none, and
  -- keeps the datum.
  local okWalk, walkable = pcall(map.isWalkableCell, map, cellX, cellY)
  if okWalk and walkable then
    local agreed, seen = nil, false
    for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
      local nx, ny = cellX + d[1], cellY + d[2]
      if map:inBounds(nx, ny) then
        local okN, nw = pcall(map.isWalkableCell, map, nx, ny)
        if okN and nw then
          -- what does the neighbour stand on?  a measured run, else its own
          -- flat floor.  A neighbour with neither ABSTAINS rather than
          -- vetoing: vetoing meant one un-flat neighbour silenced the whole
          -- vote, which is why the plaza bush kept its hole.
          local ns = Structures.runHeight(map, nx * 2, ny * 2 + 1)
          if ns == nil and Structures.flatGroundAt then
            ns = Structures.flatGroundAt(map, nx * 2, ny * 2 + 1)
          end
          if ns ~= nil then
            if not seen then agreed, seen = ns, true
            elseif agreed ~= ns then agreed = nil break end
          end
        end
      end
    end
    if agreed and agreed > 0 then return agreed end
  end
  return 0
end

VoxelScene.YAW = YAW
-- shared with the overworld battle, which stands its mons on map cells and
-- needs the same answer about what height "the floor" is there
VoxelScene.groundAt = groundAt

-- Camera-ward pull distance for billboards (and the grass rows, which
-- must keep their relative depth to feet): just enough that a leaned-back
-- slab clears the wall it leans over. The lean flattens toward top-down,
-- so the needed pull grows exactly as real occlusion stops mattering.
function VoxelScene.pull(a)
  return 6 + math.max(0, 16 * math.cos(a) - 8) / math.max(math.sin(a), 0.2)
end

-- The sheet frame and mirror flag the 2D path would draw for this pose
-- (same tables as SpriteRenderer). Shared by the billboard pass and the
-- shadow pass so a walking character's shadow swings its legs too.
local function frameFor(def, facing, phase, flip, stated)
  local SR = require("src.render.SpriteRenderer")
  local frame, mirror = 0, false
  -- A SHEET ROW THE OBJECT NAMES ITSELF OUTRANKS THE FACING TABLE.
  --
  -- `stated` is the pose's own `frame` (see statedFrame): a fixed-frame
  -- object's row, or the row a berry tree's GROWTH STAGE names.  No mirror --
  -- the mirror is the facing math's, and an object that has no facing has no
  -- left and right to swap.  nil for everybody else, so the four lines below
  -- are what every other card in the game still gets.
  local said = tonumber(stated)
  if said then return said, false end
  -- SPRITE_POKEMON objects carry a 2-frame party icon with no facing at all,
  -- so the pose tables (which index up to 5) do not apply to them
  if def.monIcon then
    return math.floor((love.timer and love.timer.getTime() or 0) * 4) % 2, false
  end
  if (def.frames or 1) > 1 then
    frame = (def.walker and phase == 1) and SR.WALK[facing]
            or SR.STAND[facing]
    mirror = facing == "right"
      or ((facing == "down" or facing == "up") and phase == 1 and flip)
  end
  return frame, mirror
end

-- The facing a pose SHOWS this camera. The flat frames are "how this pose
-- looks from the south", which is where the orbit always stands; a
-- first-person eye stands anywhere, so deep enough into the blend the
-- facing is remapped to how the pose looks from THERE -- walk behind an
-- NPC and their card wears the back sprite. Used by the camera draw and
-- the sun pass BOTH: the card the sun stored and the transform a lit card
-- reads its own shadowing with must describe the same frame, or the
-- mirror-flip half of the pair asks the map about texels the sun filed
-- under the other cheek.
-- The player's own card asks a different function for the same answer:
-- their body's bearing is what the camera is derived FROM, so it is known
-- continuously rather than as one of four directions, and measuring
-- against the compass point instead flicks the card to a profile for a
-- frame or two when the camera is spun fast (see playerFacing).
local function viewFacing(p)
  if FirstPerson.cardBlend() > 0.5 then
    if p.isPlayer then
      return FirstPerson.playerFacing(p.facing, p.px + 8, p.py + 8)
    end
    return FirstPerson.apparentFacing(p.facing, p.px + 8, p.py + 8)
  end
  return p.facing
end

-- FALLBACK ONLY (see castShadows below). Draw one entity's drop shadow as
-- a decal: its current sprite frame as a single quad, flattened onto the
-- ground along the sun line (Voxel3D.shadowMatrix). Runs inside
-- beginShadows, which supplies the translucent black; the texture is only
-- consulted for its alpha, so no palette work is needed.
local function drawShadow(sprite, px, py, facing, phase, flip, gh, lift,
                          stated)
  local def = sprite.def
  local frame, mirror = frameFor(def, facing, phase, flip, stated)
  local mesh = SpriteBillboards.shadowQuad(def, frame)
  if not mesh then return end
  -- the decal is the card squashed onto the ground, so it is anchored like
  -- the card (see drawEntity); nil anchor leaves it exactly as it was
  local half = (SpriteBillboards.halfWidth and SpriteBillboards.halfWidth(def)) or 8
  local anchor = SpriteBillboards.footAnchor and SpriteBillboards.footAnchor(def)
  Voxel3D.draw(mesh, sprite:resolveImage(),
               Voxel3D.shadowMatrix(px, py, gh, lift, mirror,
                                    anchor and half, anchor))
end

-- Where a billboard character's card stands: on the middle of its cell at
-- height `y`, pivoted at the feet and tipped back by exactly the camera's
-- pitch. The slab is built centred on its sprite plane (z = 0), so only the
-- x anchor shifts; the relief bulges symmetrically front and back of it.
--
-- Shared by the solid draw and the silhouette below, so the two can never
-- drift apart -- a silhouette standing anywhere but exactly behind the
-- figure would read as a second character.
--
-- IN FIRST PERSON the card stops leaning and starts TURNING: upright, yawed
-- about its feet to face the eye (cylindrical billboarding). A south-facing
-- card is invisible edge-on to an eye standing east of it, which no orbit
-- camera could ever do and a first-person one does constantly. The blend
-- carries one pose into the other -- the lean eases out as the yaw eases in
-- -- and cardBlend is zero for every camera that is not the first-person
-- rig, the battle's placed shot included, so nothing else moves.
-- The pitch the sprite cards lean back by -- normally the rung's own
-- camera angle, overridable in radians. VR sets the override to the top
-- rung's 75 degrees for every diorama and battle frame: a table watched
-- from a freely moving head has no one camera pitch for the cards to
-- match, and the near-upright top-rung lean is the pose that reads as
-- "standing" from anywhere around it. nil (the default, and the flat
-- screen always) leans with the rung as ever.
VoxelScene.spriteLean = nil

local function leanAngle()
  return VoxelScene.spriteLean or V.require("VoxelState").angle
end

-- `half` is the CARD's half-width; `anchor` is the middle of the FOOTPRINT it
-- stands on, which is 8 for anything standing on one cell however wide it is
-- drawn (see SpriteBillboards.footAnchor -- a surfing or cycling player in
-- Hoenn wears a 32-wide sheet on a 16-wide cell). Omitted, anchor falls back
-- to `half`, which is the 2x2-footprint reading every existing caller had.
local function billboardMatrix(px, py, y, mirror, half, anchor)
  half = half or 8
  anchor = anchor or half
  local b = FirstPerson.cardBlend()
  local m = Mat4.translate(px + anchor, y, py + anchor)
  if b > 0 then
    m = Mat4.mul(m, Mat4.rotateY(FirstPerson.cardYaw(px + anchor, py + anchor) * b))
  end
  m = Mat4.mul(m, Mat4.rotateX((leanAngle() - math.pi / 2) * (1 - b)))
  if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
  return Mat4.mul(m, Mat4.translate(-half, 0, 0))
end

local function billboardPull()
  return VoxelScene.pull(math.max(leanAngle(), 0.05))
end

-- An authored FIGURE's card -- a person the tileset draws INTO a piece of
-- furniture, cut out by the profile's mask (Structures.buildFigures). It is
-- a sprite, so it gets the sprite treatment: the mesh arrives in its own
-- local space with its feet on y = 0, and this stands it at its drawn
-- position and tips it back by exactly the camera's pitch -- the same
-- pivot-at-the-feet lean billboardMatrix gives a character, so the man on
-- the Pokemon Center couch reads face-on at every tilt like the NPCs
-- around him. No cell centring: unlike a character he is not standing on a
-- cell, he is standing where he was drawn, which may straddle two.
--
-- First person turns him at the eye like the walkers (see billboardMatrix)
-- -- about his own middle, because unlike a character card his local space
-- starts at x = 0 rather than being anchored by a -8 shift, and a yaw about
-- his edge would swing him off his seat. The width rode in on the record
-- for exactly this (ChunkMesher.buildFigureMeshes).
local function figureMatrix(f, offX, offZ)
  local b = FirstPerson.cardBlend()
  local wx, wz = f.wx + (offX or 0), f.wz + (offZ or 0)
  local m = Mat4.translate(wx, f.y, wz)
  if b > 0 and f.w and f.w > 0 then
    local half = f.w / 2
    m = Mat4.mul(m, Mat4.translate(half, 0, 0))
    m = Mat4.mul(m, Mat4.rotateY(FirstPerson.cardYaw(wx + half, wz) * b))
    m = Mat4.mul(m, Mat4.translate(-half, 0, 0))
  end
  return Mat4.mul(m, Mat4.rotateX((leanAngle() - math.pi / 2) * (1 - b)))
end

-- What the sun sees: the same card UNLEANED and flattened, exactly as
-- Voxel3D.casterMatrix does it for a character.
local function figureCaster(f, offX, offZ)
  return Mat4.mul(
    Mat4.translate(f.wx + (offX or 0), f.y, f.wz + (offZ or 0)),
    Mat4.scale(1, 1, 0))
end

-- Every figure on `map`, drawn with `draw(mesh, model, caster)`.
local function eachFigure(map, offX, offZ, draw)
  for _, f in ipairs(ChunkMesher.figures(map) or {}) do
    draw(f.mesh, figureMatrix(f, offX, offZ), figureCaster(f, offX, offZ))
  end
end

-- Draw one posed entity. Returns true if 3D geometry carried it, false
-- when nothing could be built and the caller should fall back.
-- `colors` is the 4-color world palette the entity stands under in the SGB
-- modes (nil under RED++/trueColor): the 2D path colorizes sprites with a
-- screen-space shader the voxel canvas never runs through, so the model's
-- texture gets the palette baked in instead (TerrainAtlas.forSprite).
-- `lift` raises the figure off the ground plane (ledge hops arc UP in 3D,
-- where the 2D path could only slide the sprite north).
local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,
                          lift, stated)
  local def = sprite.def
  local tex = sprite:resolveImage()
  if colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, colors) or tex
  end
  local y = gh + (lift or 0)

  -- pick the very frame the 2D path would draw (same tables). The card
  -- always faces SOUTH -- the direction the 2D game implies -- and only
  -- LEANS BACK, pivoting at its feet, by exactly the camera's pitch, so
  -- at every tilt level the sprite reads face-on like the flat game.
  -- No camera-tracking yaw: every sprite leans in parallel.
  local frame, mirror = frameFor(def, facing, phase, flip, stated)
  local mesh = SpriteBillboards.mesh(def, frame)
  if not mesh then return false end
  -- Camera-ward pull (applied per vertex in the shader, along each
  -- vertex's own eye ray, so it is a PURE depth bias with zero screen
  -- drift): lets the leaned-back head win against the wall it leans
  -- OVER while a character genuinely BEHIND a building is dozens of
  -- pixels deeper and still loses, so real occlusion works.
  -- the same card UNLEANED -- and SNUGGED, exactly as the sun stored it
  -- (castShadows draws this mesh through ShadowMap.snug) -- is where each
  -- vertex asks whether the light reached it; see ShadowMap.snug for why
  -- the lookup must match the stored transform to the letter
  --
  -- halfWidth: 8 for normal 16x16 walkers, 16 for 32x32 big dolls (Snorlax)
  -- so the card is centred on the 2x2 footprint rather than the top-left cell.
  --
  -- ...AND A GEN 3 SHEET IS WIDE WITHOUT HAVING A 2x2 FOOTPRINT. The surfing
  -- player off Route 118 wears a 32x32 sheet on one cell, and centring the
  -- card on its own half put it 8px east and 8px south of where the flat path
  -- blits it. `footAnchor` is the middle of the cell for exactly those sheets
  -- and nil for every Gen 1 / Gen 2 / Prism one, whose two matrices below are
  -- then built from the identical arithmetic they always were.
  local half = (SpriteBillboards.halfWidth and SpriteBillboards.halfWidth(def)) or 8
  local anchor = SpriteBillboards.footAnchor and SpriteBillboards.footAnchor(def)
  -- the sun stores the card UNLEANED, and the lit card looks its own shadowing
  -- up through the same transform -- "the lookup must match the stored
  -- transform to the letter", above. casterMatrix had 8 written into it, so a
  -- wide card was stored a half-width away from where it is drawn; pass the
  -- pair only where the anchor answered, so nothing else moves.
  Voxel3D.draw(mesh, tex, billboardMatrix(px, py, y, mirror, half, anchor),
               billboardPull(),
               ShadowMap.snug(Voxel3D.casterMatrix(px, py, y, mirror,
                                                   anchor and half, anchor)))
  return true
end

VoxelScene.drawEntity = drawEntity

-- The player's silhouette, for wherever the scenery is standing in front of
-- them (Voxel3D.beginGhost inverts the depth test around this call).
--
-- The same flat card the solid pass and the sun pass draw. That it has no
-- self-overlap is what makes it safe here: with the depth test inverted, a
-- mesh carrying both front and back faces would read its own back faces as
-- "behind something" and repaint the figure on open ground, occluded or
-- not. One quad cannot do that, and cannot double-blend into a mottled
-- patch either. A silhouette is an outline, so an outline is the right
-- mesh for it.
local function drawGhost(p)
  local def = p.sprite.def
  local frame, mirror = frameFor(def, viewFacing(p), p.phase, p.flip, p.frame)
  local mesh = SpriteBillboards.shadowQuad(def, frame)
  if not mesh then return end
  local tex = p.sprite:resolveImage()
  if p.colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, p.colors) or tex
  end
  local y = p.gh + (p.lift or 0)
  -- the silhouette has to stand exactly where the solid card stands or it
  -- reads as a second character, so it takes the same anchor (see drawEntity)
  local half = (SpriteBillboards.halfWidth and SpriteBillboards.halfWidth(def)) or 8
  local anchor = SpriteBillboards.footAnchor and SpriteBillboards.footAnchor(def)
  Voxel3D.draw(mesh, tex, billboardMatrix(p.px, p.py, y, mirror, half, anchor),
               billboardPull())
end

-- Render the world. `state` is the OverworldState; `vw`/`vh` the world view
-- size in world pixels; `w`/`h` the pixel size of the canvas to render
-- into; `paletteFor(map)` yields a map's 4-color world palette (nil in the
-- color modes whose atlas is already true color). Returns the finished
-- canvas, or nil if the 3D pass could not run (headless, no depth support)
-- so the caller can fall back to 2D.
-- The last live-set key, so eviction only runs when the neighbourhood
-- actually changes (a map crossing), not every frame.
local lastLiveKey = nil

-- THE RECTANGLES A MAP'S BORDER RING IS CUT AGAINST, IN ITS OWN WORLD PIXELS.
--
-- `runGeometry` suppresses ring geometry wherever another map's BODY sits,
-- because with a depth buffer the ring's standing trees would otherwise rise
-- straight through that map's flat ground -- cross into Route 1 and a wall of
-- border trees sprouts over Pallet.
--
-- That set used to be read off `state.neighbors`, the maps the engine loaded
-- around the map the PLAYER is on.  It is the right answer for exactly one
-- map in the frame: the player's.  Every other map drawn beside it needs its
-- OWN surroundings cut out of its OWN ring, and reading the player's would
-- put the holes in the wrong places.
--
-- So ask the engine the same question it asked itself.
-- `OverworldState.computeNeighbors` IS the placement arithmetic that put the
-- neighbours where they are drawn, and run from any map id it answers that
-- map's own neighbourhood, offsets and all.
--
-- TWO HOPS, PLUS THE RING'S OWN REACH, AND NOT THE CAMERA'S.  Two hops
-- because that is what the engine LOADS and draws
-- (`constants.world.neighborHops`, FieldDefaults): a body outside that set
-- is not in the frame, so cutting the ring against it would cut a hole and
-- cover nothing.  But two hops is a graph bound, not a geometric one, and on
-- the water the two come apart -- Ever Grande's ring lies over Route 126,
-- three connections away round the sea -- so the walk is also given the
-- reach below (see masksFor), which is the ring's own 96 px and stops there.
--
-- The CAMERA's reach is the one deliberately left out.  `neighborReach` is
-- half the renderer's view plus 64 px: it changes with the window, and a
-- mask that changes with the window is not a property of the map.  Keeping
-- it out is what lets the mesh, and its disk-cache key (VoxelDiskCache's
-- maskSignature), mean the same thing whether the map is the one under the
-- player's feet or one drawn beside it, so no map is ever re-meshed for
-- having been approached from a different direction, and the full slot
-- becomes as prebakeable as the body one.
--
-- What that costs is bounded and was measured: against the engine's own set
-- there is NO map it fails to mask at the flat renderer's 144x136 reach, nor
-- at 320x240; only past a 512x384 view do six roots pull in nine bodies this
-- does not cut against, and a ring quad over a body that far out is behind
-- the camera's own shoulder.  (Before the ring reach was handed to the walk,
-- that shortfall was 15 entries over 10 roots at EVERY view -- 9,568 ring
-- tiles, 51,654 quads of Petalburg's ring standing over the seabed of
-- Underwater_Route105 and 3,802 of Ever Grande's over Route 126's water.)
--
-- `def.blockPx` and not `tileset.blockTiles * 8`: the same 16 on a Gen 3
-- metatile and the same 32 on a Gen 1/Gen 2 block, but it is the field the
-- engine's own placement reads, so a mask can never disagree with where the
-- body it covers was actually drawn.  (Read as a flat 32, a Hoenn mask came
-- out twice the map's size and suppressed the ring over ground no neighbour
-- covers -- a strip of missing world along every seam.)
--
-- Measured, 81 outdoor maps: of 326,320 ring tiles carrying a shape, 113,800
-- (34.9%) sit under a directly connected body, 126,568 (38.8%) under the
-- two-hop set, and 136,136 (41.7%) once the ring's own reach is added.  The
-- 12,768-tile step from one hop to two is corner ground beyond a neighbour's
-- neighbour -- 3.9% of the ring.  When THIS map is the player's those maps
-- are drawn and the mask is exactly right; when it is a neighbour they may
-- be a hop too far to be loaded, and that corner reads as sky.  It is a
-- corner two maps out, against a whole missing tree wall one map out, which
-- is what this replaces.
local maskMemo = {}
local maskMaps, maskCompute = nil, nil

-- The two engine handles the answer needs: the map table, and the neighbour
-- walk.  Taken from the state when there is one, from the live overworld when
-- there is not, and from `Game.data` plus OverworldController's own function
-- when there is no overworld either -- so a prebake started from the settings
-- menu asks the same question the renderer does whether or not a game has
-- been loaded behind the menu.  A miss is never memoised: the world may
-- simply not be up yet.
local function maskEngine(state)
  if maskMaps and maskCompute then return maskMaps, maskCompute end
  local okG, G = pcall(require, "src.core.Game")
  G = okG and G or nil
  if not state then state = G and G.overworld or nil end
  local data = (state and state.game and state.game.data) or (G and G.data)
  local compute = state and state.computeNeighbors
  if type(compute) ~= "function" then
    -- NO OVERWORLD IS NOT NO ANSWER.  `computeNeighbors` is a pure function
    -- of the map table hanging off OverworldState, not a method of a live
    -- one, and the prebake can be started from the settings menu before a
    -- game has been loaded at all -- where, read only off `Game.overworld`,
    -- this returned nil, `ChunkMesher.bake` declined every map for want of a
    -- mask resolver, and PREBAKE VOXELS counted its way through the region
    -- baking nothing.
    local okO, OS = pcall(require, "src.world.OverworldController")
    compute = okO and type(OS) == "table" and OS.computeNeighbors or nil
  end
  if data and data.maps and type(compute) == "function" then
    maskMaps, maskCompute = data.maps, compute
  end
  return maskMaps, maskCompute
end

function VoxelScene.masksFor(map, state)
  local id = map and map.id
  if not id then return nil end
  local hit = maskMemo[id]
  if hit ~= nil then return hit or nil end
  local maps, compute = maskEngine(state)
  if not (maps and compute) then return nil end
  -- ...AND EVERY BODY THE RING CAN ACTUALLY TOUCH, WHICHEVER HOP IT IS ON.
  --
  -- Two hops is the set the engine LOADS, not the set that can stand under
  -- this map's ring, and on the water the two come apart: Ever Grande's ring
  -- lies over Route 126, which is three connections away round the sea, and
  -- a two-hop walk does not cut it.  `computeNeighbors` takes a reach for
  -- exactly this and keeps walking while a body still overlaps the root's
  -- rect inflated by it, so the ring's OWN extent is the honest number to
  -- hand it: ChunkMesher builds `r = RING * 4` tiles of ring at eight pixels
  -- a tile, and nothing further out than that can be under any of it.
  --
  -- It stays a property of the MAP -- 96 is this mod's constant, not the
  -- camera's -- and it is the reach the ENGINE's own set already had: with
  -- it, the maps this cuts against are exactly the maps the frame draws, on
  -- every one of the 81 outdoor maps, at the flat renderer's 144x136 reach
  -- and at a 320x240 one.  Without it, ten roots masked LESS than the frame
  -- drew -- 9,568 ring tiles, 3,168 of them Ever Grande's standing over
  -- Route 126's water, which is a tree in the sea.
  local RING_PX = 96
  local okN, list = pcall(compute, maps, id, 2, RING_PX, RING_PX)
  if not (okN and type(list) == "table") then
    maskMemo[id] = false
    return nil
  end
  local masks = {}
  for _, n in ipairs(list) do
    local d = maps[n.id]
    if d and tonumber(d.width) and tonumber(d.height) then
      local px = tonumber(d.blockPx) or 32
      masks[#masks + 1] = { n.ox, n.oy,
                            n.ox + d.width * px, n.oy + d.height * px }
    end
  end
  maskMemo[id] = masks
  return masks
end

-- Map data is static for the run, so the answer is too; this exists for a
-- host that swaps the cartridge under us (the dev console's map reload).
function VoxelScene.forgetMasks()
  maskMemo, maskMaps, maskCompute = {}, nil, nil
end

-- ...and the prebake pass asks the same question, so a baked FULL entry
-- carries the key the live request will look it up under (ChunkMesher.bake).
ChunkMesher.masksFor = VoxelScene.masksFor

-- Request everything `state`'s frame wants and evict what it no longer
-- does; returns the current map's terrain mesh (or nil while it builds)
-- and the neighbour meshes ready to draw. render() calls this for the
-- frame it is drawing, and the pipeline's update hook calls it EVERY
-- frame -- including the frames a warp's Transition covers, when the
-- world pass is off. That update-side call is what lets a door fade hide
-- the destination's build: the map swaps behind the fade, and waiting
-- for the first visible frame to request meshes would show the flat
-- fallback while the first slices run.
function VoxelScene.prefetch(state)
  if state and state.map and state.map.def and state.map.def.generation==4 then return nil end
  local Voxel = V.require("VoxelState")

  -- The live set is the current map plus its rendered neighbours. When
  -- it changes, everything outside it (and the previous set, which
  -- ChunkMesher retains so stepping into a house keeps the town warm)
  -- is evicted -- meshes released, analysis dropped -- so memory stays
  -- bounded by the neighbourhood instead of growing with every area
  -- ever visited.
  local liveKey = state.map.id
  local live = { [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do
    live[nb.map.id] = true
    liveKey = liveKey .. "|" .. nb.map.id
  end
  if liveKey ~= lastLiveKey then
    lastLiveKey = liveKey
    ChunkMesher.setLive(live)
    -- RED++ bakes one atlas per map, so its animated copy is per map too
    -- and is bounded by the same neighbourhood
    TerrainAtlas.setLive(live)
  end

  -- masks: where the bodies around a map sit, so its border ring is
  -- suppressed under them (see masksFor above, and runGeometry).  Every map
  -- in the frame gets its own set now, this one included.
  --
  -- `masksFor` answers nil only when it cannot reach the engine's own map
  -- table or `computeNeighbors` -- a host that has not published them, or a
  -- cartridge swapped under us mid-frame.  NIL IS NOT AN EMPTY MASK SET: an
  -- unmasked full build stands this map's border trees up through every
  -- neighbour's ground, which is the failure the mask exists to prevent.  So
  -- the degenerate case falls back to the derivation this pass used before
  -- the ring was given to neighbours -- the rectangles of the bodies the
  -- engine has ALREADY placed around the player, which is exactly the old
  -- answer for the old (and only the old) map, the player's.
  local masks = VoxelScene.masksFor(state.map, state)
  if not masks then
    masks = {}
    for _, nb in ipairs(state.neighbors or {}) do
      local px = (tonumber(nb.map.def and nb.map.def.blockPx)
                  or (tonumber(nb.map.tileset and nb.map.tileset.blockTiles) or 4) * 8)
      masks[#masks + 1] = { nb.ox, nb.oy,
                            nb.ox + nb.map.def.width * px,
                            nb.oy + nb.map.def.height * px }
    end
  end

  -- Builds are asynchronous (ChunkMesher.pump runs in the pipeline's
  -- update): request what this frame wants and draw what is ready.
  -- The current map draws its body-only mesh while the full one (the
  -- border ring) is still building -- a seam crossing promotes a
  -- neighbour whose body is already cached, and the ring pops in a few
  -- frames later, mostly hidden behind the map just left. A neighbour
  -- missing its body-only mesh draws its cached FULL mesh instead -- a
  -- crossing demotes the map just left, and it must not vanish from
  -- behind the player while its body variant builds; its ring is
  -- already masked out under this map's body, so the stand-in is safe.
  -- The water surface rides along with whichever variant answers: it was
  -- cut out of that build's own geometry (ChunkMesher.pair), so the two
  -- always come from the same slot and a lake is never drawn twice or left
  -- as a hole.
  ChunkMesher.request(state.map, false, masks, true)
  local terrain, water = ChunkMesher.pair(state.map, false)
  if not terrain then
    terrain, water = ChunkMesher.pair(state.map, true)
  end
  -- ...AND A NEIGHBOUR HAS A HORIZON TOO.
  --
  -- Every neighbour used to be meshed `bodyOnly`: the current map supplies
  -- the ring around the view and a neighbour contributes its body.  That is
  -- the 2D path's shape and on a flat screen it is right, because the flat
  -- renderer tiles the border patch to the edge of the SCREEN and the current
  -- map's ring is the horizon for the whole frame.
  --
  -- A diorama camera sees several map-widths out, and there each neighbour
  -- simply STOPS at its own body edge -- a straight line of town with the sky
  -- behind it.  In-game: stand anywhere on Route 101 and look north at
  -- Oldale, or west from Oldale at Route 102 -- "many of the towns still are
  -- missing their tree borders".
  --
  -- Region-wide, 81 outdoor maps: 190,184 border-ring TILES carry a shape
  -- that no body around them covers -- 47,546 cells of modelled tree wall
  -- that got built for exactly one map per frame.  On the frames themselves,
  -- under POKEPORT_SKY_FLAT: giving every neighbour its own ring turns 50,506
  -- pixels of void into terrain on the Oldale frame and 36,128 on Route
  -- 101's, and turns none of it the other way.
  --
  -- So a neighbour is asked for its FULL mesh, and its own masks do the
  -- asymmetry for nothing: the side facing this map is covered by this map's
  -- body and is cut away, so what actually gets built is the ring on the
  -- sides facing OUT -- which is the only part of it anyone can see.
  --
  -- This is not extra work spread over the walk, it is the SAME work moved
  -- earlier: the full mesh a map needs when you step onto it is now already
  -- built and cached from when it was a neighbour, so a seam crossing costs
  -- nothing where it used to cost a whole rebuild.  A neighbour with no full
  -- mesh yet still draws its body variant if one happens to be cached.
  --
  -- And the same rule as above about a nil answer, with the same reason and
  -- a different remedy: there is no older derivation for a NEIGHBOUR's own
  -- surroundings to fall back to, so a neighbour whose masks cannot be
  -- resolved is meshed exactly as it was before this change -- body only,
  -- no ring.  It loses its horizon, which is the defect this pass fixes; it
  -- does not grow a tree wall through the map the player is standing on,
  -- which would be a worse one.
  local nbMesh, nbWater = {}, {}
  for i, nb in ipairs(state.neighbors or {}) do
    local nbMasks = VoxelScene.masksFor(nb.map, state)
    if nbMasks then
      ChunkMesher.request(nb.map, false, nbMasks)
      nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, false)
      if not nbMesh[i] then
        nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, true)
      end
    else
      ChunkMesher.request(nb.map, true)
      nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, true)
    end
  end
  Voxel.ready = terrain ~= nil
  return terrain, nbMesh, water, nbWater
end

-- AN OBJECT THE CARTRIDGE NEVER DRAWS IS NOT PART OF THE CAST.
--
-- In-game location: UNDERWATER, THE SEAFLOOR CAVERN BAY -- the submarine
-- EXPLORER 1, cells (5,4) (6,4) (7,4) (8,4).
--
-- The hull is drawn in the MAP ART (Underwater metatiles 736-747, four cells
-- across and three rows deep), and Emerald stands four object events under it
-- so that talking to any of its four cells prints "\"SUBMARINE EXPLORER 1\"
-- is painted on the hull."  All four are graphics id 100 carrying movement
-- type 0x4C, and 0x4C is the cartridge's own HIDDEN type: an object that
-- exists for its collision and its script and is never blitted.  This pass
-- drew all four, so a diver arriving in the bay was met by four copies of a
-- character standing in a row over the sub -- reported as "the submarine
-- shows 4 player characters".  The count is the CARTRIDGE's, not a
-- duplication: four object events, one per cell of a four-cell hull.
--
-- 0x4C is read, not guessed.  Sixteen object events in Hoenn carry it and
-- NINE are the invisible KECLEON -- Fortree City 1, Route 118 2, Route 120 6
-- -- whose shared script opens `checkitem 288`, the DEVON SCOPE, "a device
-- that signals any unseeable POKEMON", and whose reveal movement is literally
-- `set_visible` / `set_invisible` flashing before `setwildbattle`.  The other
-- three are one hidden helper each in Devon Corp 3F, Steven's House and the
-- Mossdeep Space Center.  No other movement type shares 0x4C's step callback.
--
-- The flat 2D pass has always honoured `e.hidden` -- the field a script's
-- set_visible / set_invisible writes -- and this pass never did, which is the
-- same divergence a second time.  Both readings are folded in here, in the
-- cartridge's own order of authority:
--
--   e.hidden == true    a script has hidden it                 -> not drawn
--   e.hidden == false   a script has REVEALED it               -> drawn
--                       (a Kecleon, once the DEVON SCOPE is out)
--   e.hidden == nil     nobody has spoken, so the template's
--                       own movement type answers
--
-- `gen3MovementType` is asked first because `setobjectmovementtype` writes
-- that and leaves the template alone.  A Gen 1, Gen 2 or Prism object carries
-- no `movementType` at all, so this is nil for every one of them and the
-- answer falls back to exactly the `e.hidden` the flat path already gave.
local GEN3_MOVEMENT_HIDDEN = 0x4C

-- ------- THE BERRY PLOTS
--
-- IN-GAME LOCATION: ROUTE 104's berry patch, cells (34,6), (35,6) and (36,6)
-- -- the three plots on the soil strip beside the PRETTY PETAL FLOWER SHOP,
-- which is the frame the report arrived with.  The same three functions cover
-- all 88 of Hoenn's plots.
--
-- Reported from play: "ensure berry trees and sprouts appear as sprites do
-- currently theyre not appearing with voxels on and i just see mounds of
-- dirt".
--
-- THE MOUND IS THE PLOT, NOT THE PLANT.  Emerald marks a berry plot's own
-- cell impassable -- you cannot walk into the tree -- and it is otherwise an
-- ordinary MB_NORMAL cell, so the cell rules read it as a solid mass and
-- stand its drawing up.  Measured over all 518 maps: of the object events
-- that carry the berry tree's graphics row, 87 stand on a cell the shape pass
-- made non-flat -- 48 `cylinder`, 39 `cliff` -- and `buildCylinders` lathes
-- the plot's own dark soil art into a 16px round hull.  That hull, wearing
-- the soil metatile's own two tones at the terrain lighting's two levels, is
-- what the report calls a mound of dirt.
--
-- THE PLANT IS AN OBJECT EVENT STANDING ON THAT SAME CELL.  The mod's own
-- data file has said so from the start -- data/gen3_shapes.lua, at
-- MB_BERRY_TREE_SOIL: "Berry soil is here too: the plant growing in it is an
-- object sprite, not part of the metatile."  And it is not dropped anywhere:
-- measured, every berry tree template in Hoenn carries movement type 12
-- (FACE_DOWN), not 0x4C, so `castHides` answers false for all of them; they
-- are in `state.entities` like every other live NPC; and their card builds.
--
-- What is wrong is WHERE THEIR FEET GO.  `groundAt` answers the floor the
-- hull STANDS ON (the terrace, or the stamp `buildCylinders` recorded under
-- it), not the hull's top, so the card is planted at the BOTTOM of a solid
-- 16px hull that fills its own cell.  A billboard leans back by exactly the
-- camera's pitch (see billboardMatrix), so a 32px card rises only
-- 32*cos(90 - pitch) above its feet: 8px at the 15-degree rung, 18px at 35,
-- 25px at 50.  At every diorama rung below the first-person one the whole
-- card -- minus the sheet's empty top margin, which is the only part that
-- clears -- is inside the mound, and the depth test eats it.  Nothing is
-- hidden, nothing is mis-framed, nothing is at zero scale: it is buried.
--
-- THE MOUND IS GONE AS OF g3-plot-298, AND THIS IS WHERE IT WENT.  The
-- paragraph that used to stand here recorded the diagnosis and refused the
-- fix -- "a berry plot is flat tilled soil in the cartridge, this mod's own
-- behaviour table already says `[0xA0] = "ground"`, and the cell only reads
-- as a mass because its collision bit is set for the object standing on it.
-- Correcting that moves shape state on 87 cells, and this round is under a
-- geometry freeze" -- and it was reported again from play, in the same words:
-- "berrys trees are properly animated though but theyre sitting on large
-- mounds of dirt when they shouldnt".
--
-- The correction is where the diagnosis said it was, in the SHAPE pass, and
-- it is keyed on the byte and nothing else: `Gen3.isBerryPlot` (0xA0
-- MB_BERRY_TREE_SOIL), three rules in `Gen3.classAt` and
-- `Structures.capGen3Rock` that stop a plot being lathed, stood up or capped,
-- and `Structures.levelGen3Plots`, which levels what is left with the ground
-- beside it.  DERIVED, over all 88 of Hoenn's berry trees: the plot's drawn
-- top was 4 to 20 pixels above the ground it is tilled into on 69 of them and
-- flush on 19; it is now flush on all 88, no plot cell carries a stamp or a
-- run, and the plant's feet sit exactly on the soil (0px, all 88 -- they were
-- 16px under it on 3, 8px on 2, 2px on 1, and 4 to 32px above it on 69).

-- THE TOP OF THE HULL STANDING ON A CELL, asked of the only thing that
-- knows: the ROUND STAMP the mesher expands there.
--
-- The shape record cannot answer this and it was tried first.  Route 104
-- (3,22) and (22,41) carry byte-identical shapes -- class=cylinder, h=16,
-- base=16, stamp=16, skip=true -- and the mesher draws a hull on one and
-- flat ground on the other, because `buildCylinders` decides which cells get
-- a STAMP and only a stamped cell grows a hull.  Any rule read off `shape.h`
-- plus a class height therefore floats a plant wherever it guesses wrong,
-- and a floating plant is a worse frame than a buried one.
--
-- So this reproduces ChunkMesher's own placement, line for line: the stamp
-- centred on THIS cell, lifted to `my` (the stamp's own base, overridden on
-- a Gen 3 skip cell by the floor painted under it -- the branch whose
-- comment is "a stamp can stand above the floor" and its Mossdeep sequel),
-- plus the tallest y in the stamp's quads.  Verified against the geometry
-- the mesher actually emits, cell by cell, over all 88 berry trees in Hoenn:
-- 48 cells carry a stamp and the prediction equals the measured top on every
-- one of them, exactly; 22 carry none and their measured top already equals
-- what groundAt answers; and 18 stand on a COLUMN rather than a stamp (a
-- cliff face, or a hull anchored on a neighbour) where this answers nil and
-- nothing moves -- named in NOTES as the half this round does not reach.
--
-- CENTRED ON THE CELL, not merely covering it.  A stamp's radius is 16, so
-- its footprint spills into the neighbours: at Route 104 (22,41) the covering
-- set includes the 32px TREE hulls of the row above, and taking their top
-- would stand the plant on a tree.  The centre test is what makes the answer
-- this cell's own drawing.
--
-- Memoised per cell against the Structures analysis (weak-keyed, so a map
-- the cache evicts takes its index with it): the scan is 782 comparisons and
-- one stamp's quads, once per plot, and there are at most a handful of plots
-- in view.
local hullTops = setmetatable({}, { __mode = "k" })

local function drawnTop(map, cellX, cellY)
  local okS, S = pcall(Structures.forMap, map)
  if not (okS and type(S) == "table" and S.roundStamps) then return nil end
  local memo = hullTops[S]
  if memo == nil then memo = {}; hullTops[S] = memo end
  local k = cellY * 8192 + cellX
  local hit = memo[k]
  if hit ~= nil then return hit or nil end
  local mx, mz = cellX * 16 + 8, cellY * 16 + 8
  local best = nil
  for _, st in ipairs(S.roundStamps) do
    if st.mx == mx and st.mz == mz then
      local sr = st.r or 8
      local my = tonumber(st.my) or 0
      if S.isGen3 and S.skip then
        local acx = math.floor((mx - sr) / 16) * 2
        local acz = math.floor((mz - sr) / 16) * 2
        if S.skip[(acz + 64) * 4096 + (acx + 64)] then
          local okF, fy = pcall(Structures.stampGround, map, acx, acz)
          if okF and type(fy) == "number" then my = fy end
        end
      end
      local hi = nil
      for _, q in ipairs(st.quads or {}) do
        for j = 1, 4 do
          local y = q[j] and q[j][2]
          if y and (hi == nil or y > hi) then hi = y end
        end
      end
      if hi then
        local top = my + hi
        if best == nil or top > best then best = top end
      end
    end
  end
  memo[k] = best or false
  return best
end

-- A PLANTED OBJECT STANDS ON THE DRAWING, NOT INSIDE IT.
--
-- Asked of the BERRY TREE ALONE, and by IDENTITY rather than by class.  The
-- engine hangs `berryTreeId` on exactly these objects and on nothing else
-- (OverworldState.pooledNPC, through Gen3Commands.isBerryTree, which matches
-- the graphics ids the import found by the frame table's own shape); the flat
-- path reads the very same field to decide whether a plot is empty.  Identity
-- is the only reliable test here -- it is the conclusion the player's own
-- invisibility forced on castHides, for the same reason -- because a CLASS
-- test would also lift the three other objects in Hoenn that stand on a
-- `cylinder` cell: Southern Island's Latios, Birth Island's Deoxys triangle
-- and one of Devon Corp 3F's hidden helpers.  Nobody reported those, nobody
-- measured them, and one of them is never drawn at all.
--
-- A LIFT ONLY, NEVER A LOWERING.  Measured against the mesher's own emitted
-- geometry over all 88 of Hoenn's berry trees: 48 stood on a lathed hull and
-- every one of them rose by 14px (40 of them) or 15px (8) -- the hull's own
-- measured height, not a tuned constant, and the whole distribution was those
-- two adjacent values with nothing else in it.  The other 40 did not move:
-- 22 already stood on the top of what was drawn at their cell, and 18 stood
-- on a COLUMN whose top `drawnTop` declines to guess at.  Nothing anywhere is
-- lowered, so no plant can be sunk into a bank by this.
--
-- AND SINCE g3-plot-298 IT IS INERT ON EVERY BERRY TREE IN HOENN, which is
-- the outcome that was wanted.  A plot is no longer lathed, so no stamp is
-- centred on one, so `drawnTop` answers nil and this returns `gh` unchanged
-- -- DERIVED, all 88, 0 stamped tiles and 0 run tiles per plot cell.  It is
-- kept rather than deleted because it is the RULE and not the workaround: it
-- says a planted object stands on the drawing at its cell, and the moment a
-- profile pins a plot to something with a hull that is still the right
-- answer.  It costs one nil field read per berry tree per frame.
--
-- nil for every Gen 1, Gen 2 and Prism object, which carry no `berryTreeId`
-- at all, and for a Gen 3 object standing on ordinary flat soil (`drawnTop`
-- answers nil for a flat cell), so both are left at exactly the height they
-- were drawn at before.
local function plantedOn(map, e, gh)
  if e == nil or e.berryTreeId == nil then return gh end
  if not Gen3.mapIsGen3(map) then return gh end
  local top = drawnTop(map, e.cellX, e.cellY)
  if type(top) == "number" and type(gh) == "number" and top > gh then
    return top
  end
  return gh
end

-- The growth stage this plot is at, or nil when the question does not apply.
--
-- Asked EVERY FRAME, never remembered: "a plot's answer changes while you are
-- standing there.  A tree is planted, grows and is picked without the map
-- reloading" -- which is the flat path's own comment over `plotEmpty`, and
-- this is the same read through the same function.  0 is an empty plot.
--
-- pcall'd exactly as the flat path pcalls it: on an engine whose
-- Gen3Commands has no berry reader the call fails, this answers nil, and
-- every branch below behaves as it did before the patch.
local function berryStage(e)
  local id = e and e.berryTreeId
  if id == nil then return nil end
  local ok, stage = pcall(function()
    local G = require("src.core.Game")
    return require("src.script.Gen3Commands").berryTreeStage(G and G.save, id)
  end)
  if not ok then return nil end
  return tonumber(stage) or 0
end

-- The frame this entity's own drawing STATES, as against the one its facing
-- implies.  nil for everybody else, in every generation.
--
-- TWO SOURCES, in the engine's own order of authority:
--
--   1. `e.fixedFrame` -- the engine's published channel for an object that
--      draws ONE sheet row and has no facing at all.  `NPC:draw` branches on
--      it into `SpriteRenderer:drawFixedFrame`, whose own comment says "no
--      facing, no walk cycle... the object's movement data (not its facing)
--      says which one it is, so the ordinary facing math must never touch
--      it".  `NPC:pose` does not return it, so `posesOf` never saw it and
--      `frameFor` -- whose comment promises "the very frame the 2D path would
--      draw (same tables)" -- could only ever answer the facing table.  That
--      is a real divergence for every fixed-frame object, berries aside.
--
--   2. A BERRY TREE'S GROWTH STAGE.  Emerald draws a berry tree from two
--      things, and neither is its facing: a sheet chosen by the BERRY and a
--      frame chosen by the STAGE.  The import records the second of those
--      verbatim -- `constants.gen3Berries.trees.stages[stage]` is the list of
--      frames that stage cycles, read off the tree's own animation table --
--      precisely "so that the step that draws it is mechanical".  This is
--      that step, for this pass.
--
--      Guarded on the sheet actually having frames to choose between: if the
--      engine hands a berry tree a ONE-frame sheet (a per-stage sprite chosen
--      upstream, which `pose()` would already be carrying for both paths),
--      `frames <= 1`, this declines, and `frameFor` answers 0 exactly as it
--      does today.  The two readings can never fight.
--
--      The first frame of the stage, not the second: stages 2..5 sway between
--      two frames on the cartridge's own animation clock, and this pass has
--      no clock for that object.  A still plant, at the right stage.
--      GEN 3 ONLY, and deliberately.  `fixedFrame` is not a Gen 3 field --
--      it is the extractor's row pin for POLISHED's ball/cut/fruit sheet,
--      where a cut tree is frame 1 and a fruit tree frame 2 -- and those
--      objects have the very same divergence in this pass: the flat path
--      blits their stated row and the diorama draws frame 0, the ball.  That
--      is a real defect and it is NOT fixed here, because it is a Gen 2 /
--      Prism behaviour change this round has no way to measure, and the
--      standing rule is that anything outside a Gen 3 arm must be PROVEN
--      neutral for all three.  Recorded in NOTES (g3-orchard-289) so the next
--      reader does not mistake it for a symptom of this one.
local function statedFrame(map, e)
  if e == nil then return nil end
  local fixed = tonumber(e.fixedFrame)
  if fixed then return fixed end
  -- Fixed rows are also published by Gen2's ball/cut/fruit sheet. Only the
  -- dynamic growth-stage lookup below belongs to Gen3.
  if not Gen3.mapIsGen3(map) then return nil end
  if e.berryTreeId == nil then return nil end
  local sp = e.sprite
  local def = sp and sp.def
  if not (def and (tonumber(def.frames) or 1) > 1) then return nil end
  local stage = berryStage(e)
  if not stage or stage <= 0 then return nil end
  local ok, frame = pcall(function()
    local G = require("src.core.Game")
    local c = G and G.data and G.data.constants
    local trees = c and c.gen3Berries and c.gen3Berries.trees
    local row = trees and trees.stages and trees.stages[stage]
    return row and tonumber(row[1]) or nil
  end)
  return (ok and frame) or nil
end

VoxelScene.statedFrame = statedFrame

local function castHides(e, isPlayer)
  if e == nil then return false end
  local told = e.hidden
  if told ~= nil then return told and true or false end
  -- A BERRY PLOT WITH NOTHING IN IT IS SOIL, NOT A TREE.
  --
  -- The flat path has always honoured this and this pass never did, which is
  -- the same divergence `e.hidden` was -- a third time.  OverworldState's
  -- draw loop calls it `plotEmpty`: "all 88 of Hoenn's plots drew the same
  -- tree sprite whatever was -- or was not -- growing in them, and on a fresh
  -- save that is nothing at all, because the cartridge blanks every one of
  -- its 128 tree slots at new game."  HIDDEN RATHER THAN ABSENT, for the same
  -- reason it is there: the object still blocks its cell and pressing A on it
  -- still runs the script that plants a berry, and none of that is this
  -- pass's business.  Only the card is dropped.
  --
  -- It is asked HERE and not at spawn because the answer changes while you
  -- are standing there -- plant, water, pick -- and castHides runs once per
  -- entity per frame, which is exactly the flat path's cadence.
  --
  -- Ordered after `e.hidden` and before the movement type, because a script
  -- that has taken a specific object off screen outranks the plot's own
  -- state, and because an empty plot is never the player.
  local stage = berryStage(e)
  if stage ~= nil and stage <= 0 then return true end
  -- ...AND THE MOVEMENT TYPE IS ASKED ONLY OF AN OBJECT EVENT.
  --
  -- MOTIVATED BY THE PLAYER GOING INVISIBLE IN LITTLEROOT TOWN.
  --
  -- 0x4C is a value in `gObjectEventGraphicsInfo`'s movement table, and the
  -- player is not an object event -- they are the engine's own actor, with
  -- no entry in it.  Anything named `movementType` reachable from the player
  -- is therefore not that table's index and must not be read as one: a
  -- single collision drops the one actor the camera is following, and the
  -- frame has no player in it at all.
  --
  -- `e.hidden` is still honoured for the player, because a SCRIPT hiding
  -- them (Gen3Commands' `player.hidden = (not visible) or nil`) is a
  -- cutscene statement the flat path obeys and the diorama must too.
  -- The caller passes `isPlayer` because identity is the only reliable test:
  -- `Player` advertises no flag of its own, and every duck-typed guess
  -- (`e.isPlayer`, `e.kind`) is a field that may simply not be there.
  if isPlayer then return false end
  local mt = tonumber(e.gen3MovementType)
  if mt == nil then
    local d = e.def
    mt = d and tonumber(d.movementType) or nil
  end
  return mt == GEN3_MOVEMENT_HIDDEN
end

-- Capture every entity's pose for this frame. pose() advances the hop /
-- surf bob / spinner timers, so it must be called EXACTLY once per entity
-- per frame -- the sun pass and the character pass then read the same
-- answer instead of disagreeing by a tick. Ghost NPCs live on a neighbour
-- map, so their position, ground lookup and palette all belong to that
-- map. pose() returns the VISUAL y (ledge hops arc it, surfing bobs it);
-- the difference from the entity's base y becomes vertical LIFT in 3D, so
-- a hop rises off the ground instead of sliding north.
-- Returns the pose list and, separately, the PLAYER's entry in it (nil
-- during a Fly animation, which draws the player itself and is skipped
-- below). Only that one entry gets the see-through treatment: NPCs and the
-- ghosts standing on a neighbour map are left to honest occlusion, because
-- it is only your own character you cannot afford to lose behind a roof.
local function posesOf(state, spriteColors)
  local colors = spriteColors(state.map)
  local posed = {}
  local me = nil
  for _, g in ipairs(state.ghosts or {}) do
    -- pose() ADVANCES the hop / surf-bob / spinner timers, and the contract
    -- above is that it runs exactly once per entity per frame -- so a hidden
    -- actor is still POSED and only its card is dropped.  Posing it
    -- conditionally would leave it a frame behind every time it reappeared.
    local sprite, vx, vy, facing, phase, flip = g.npc:pose()
    if not castHides(g.npc) then
      local gmap = g.map or state.map
      posed[#posed + 1] = {
        sprite = sprite, px = vx + g.ox, py = g.npc.py + g.oy,
        facing = facing, phase = phase, flip = flip,
        -- ...on the drawing its cell became, where that is a berry plot (see
        -- plantedOn).  A ghost stands on ITS OWN map, so the question goes to
        -- that map exactly as the ground lookup beside it does.
        gh = plantedOn(gmap, g.npc,
                       groundAt(gmap, g.npc.cellX, g.npc.cellY,
                                g.npc.elevation, vx + g.ox, g.npc.py + g.oy)),
        -- the frame this entity's drawing states, when it states one; nil
        -- leaves frameFor answering exactly the facing table it always did
        frame = statedFrame(gmap, g.npc),
        lift = g.npc.py - vy, colors = spriteColors(gmap),
      }
    end
  end
  for _, e in ipairs(state.entities or {}) do
    if not (state.flyAnim and e == state.player) then
      local sprite, vx, vy, facing, phase, flip = e:pose()
      if not castHides(e, e == state.player) then
        posed[#posed + 1] = {
          sprite = sprite, px = vx, py = e.py,
          facing = facing, phase = phase, flip = flip,
          gh = plantedOn(state.map, e,
                         groundAt(state.map, e.cellX, e.cellY, e.elevation,
                                  vx, e.py)),
          frame = statedFrame(state.map, e),
          lift = e.py - vy, colors = colors,
        }
        if e == state.player then
          me = posed[#posed]
          -- marked so the camera draw can leave the card out in first
          -- person, where it would fill the lens from inside; the SUN pass
          -- reads the same list and deliberately does not check the mark
          me.isPlayer = true
        end
      end
    end
  end
  return posed, me
end

-- ------- the glint's drive
--
-- A reflection is something the VIEWPOINT does, so the window glint is fed
-- by the camera's own travel rather than by a clock: its phase advances
-- with distance covered and its strength fades in over a few steps of
-- walking and back out within a beat of standing still. Stand still and
-- the glass is still; move and the light crosses it.
-- The rate is slow on purpose: the sweep pattern lives in the pane's own
-- texels (see the scene shader), so this is a FRACTION of a texel per world
-- pixel walked -- one full pass of the glint across a pane per eight or so
-- cells of travel, with no frame ever jumping it far enough to strobe.
-- The camera's own vertical follow: where the view centre currently sits,
-- and the map it was measured on (a map change snaps rather than glides).
local groundFollow = { y = nil, map = nil }

VoxelScene.GLINT_RATE = 0.05     -- radians of sweep per world pixel travelled
VoxelScene.GLINT_IN = 0.12      -- strength gained per moving frame
VoxelScene.GLINT_OUT = 0.08     -- and lost per resting frame

function VoxelScene.glintStep(g, cx, cy)
  local dist = 0
  if g.x then
    dist = math.abs(cx - g.x) + math.abs(cy - g.y)
  end
  g.x, g.y = cx, cy
  g.phase = ((g.phase or 0) + dist * VoxelScene.GLINT_RATE) % (2 * math.pi)
  if dist > 0.05 then
    g.amp = math.min(1, (g.amp or 0) + VoxelScene.GLINT_IN)
  else
    g.amp = math.max(0, (g.amp or 0) - VoxelScene.GLINT_OUT)
  end
  return g
end

local glint = {}

-- ------- the cast
--
-- Everybody standing on the map: the walkers, and the authored FIGURES the
-- tileset draws into its own furniture (they ARE characters as far as the
-- artwork is concerned, just ones drawn by the tileset instead of by a
-- sprite sheet, so they get the same lean and the same camera-ward pull).
--
-- One function because it is drawn TWICE and the two must be identical: once
-- into the frame, and once into the water's reflection copy (see drawWater --
-- Gen 1 draws people over the world, and water is world, so the cast cannot
-- be composited before the water it has to appear in).
--
-- Characters carry no wireframe out here, whatever the V-GRID row says. The
-- seams are what makes the WORLD read as built out of voxels, and the people
-- walking around in it are the one thing that should read as drawn instead --
-- a grid over a 16x16 sprite lands a line every couple of display pixels and
-- turns a face into a mesh. (The battle pass makes the opposite call for its
-- own combatants, deliberately -- see BattleBillboard.)
--
-- Sprite sheets until the figure pass: their texture coordinates mean
-- nothing to the tileset-shaped glass mask, so the glass is off or the
-- panes' atlas positions stripe the cast with lamplight at night.
local function drawCast(state, posed, atlasFor)
  Voxel3D.glass(false)
  Voxel3D.seams(false)
  -- Characters, normally depth-tested: the camera-ward pull inside
  -- drawEntity resolves the lean-over-the-wall-in-front case, and a
  -- character genuinely behind a building is far deeper and loses the
  -- test, so buildings and trees really occlude.
  --
  -- In first person two of them change: the player's own card is left out
  -- (the eye is standing in it), and every other card wears the frame its
  -- pose SHOWS this eye (viewFacing) rather than the one it shows the
  -- south. Both run through here, so the water's reflection copy -- drawn
  -- by this same function -- agrees with the frame to the pixel.
  local hideMe = FirstPerson.hidePlayer()
  for _, p in ipairs(posed) do
    if not (p.isPlayer and hideMe) then
      drawEntity(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,
                 p.colors, p.lift, p.frame)
    end
  end
  -- back on for everything textured from the atlas again -- figures, grass
  -- and flowers all sample it, where the mask's coordinates are honest
  Voxel3D.glass(true)
  -- Figures after the walkers, so a player standing in front of the couch
  -- wins the overlap -- the order the flat game draws them in.
  local figPull = billboardPull()
  eachFigure(state.map, 0, 0, function(mesh, model, caster)
    Voxel3D.draw(mesh, atlasFor(state.map), model, figPull,
                 ShadowMap.snug(caster))
  end)
  for _, nb in ipairs(state.neighbors or {}) do
    eachFigure(nb.map, nb.ox, nb.oy, function(mesh, model, caster)
      Voxel3D.draw(mesh, atlasFor(nb.map), model, figPull,
                   ShadowMap.snug(caster))
    end)
  end
  -- and the seams are back on for the terrain art that follows: grass and
  -- flowers are the world's own drawing, not people
  Voxel3D.seams(true)
end

-- ---- THE RINGS A FOOT LEAVES ON THE WATER ---------------------------------
--
-- IN-GAME SITUATION: WALKING THROUGH THE SHALLOW WATER ON ROUTE 104 -- and,
-- in the frame that motivated this, standing on the wooden bridge over it
-- while two NPCs stand in the shallows off the side branch.  Every step that
-- finishes on a rippling cell leaves a ring, the cartridge's animation
-- outlives the step, so several are alive at once (OverworldState:spawnRipple
-- / updateRipples own all of that -- nothing here changes WHEN a ring is
-- made, only where and in what order it is drawn).
--
-- WHY IT IS GEOMETRY AND NOT AN OVERLAY.  These rings used to be composited
-- by ctx.drawFx, the 2D seam the other seven field effects ride, which runs
-- over the FINISHED scene -- terrain, water and every character card already
-- down.  A ring therefore painted ON TOP of the player standing in it, and
-- stood upright and unforeshortened besides.  Drawn here instead it is an
-- ordinary quad in the world: it foreshortens with the ground because it IS
-- lying on the ground, and it is occluded by whatever is drawn after it.
--
-- A FUTURE PLANAR REFLECTION PASS GETS THESE FOR FREE, and should.  The ring
-- is now real geometry sitting at the water plane, so a pass that mirrors the
-- scene about that plane finds it where the mirrored and the original copy
-- coincide.  It is deliberately NOT painted into the CURRENT screen-space
-- mirror (VoxelScene.drawWater's `cast` callback, which runs before this):
-- that copy exists so upright sprites standing BESIDE the water have colour
-- for the march to find, and a disc lying flat ON the mirror would be
-- doubled onto itself rather than reflected.

-- THE HEIGHT THE RING LIES AT, and why it is the flat surface rather than the
-- wave crest.
--
-- The water surface this mode draws is a heightfield: one-world-pixel columns
-- standing up to Water.WAVE_HEIGHT (5, STATED) above the plane.  But those
-- columns are not geometry at all -- the mesh is still one flat quad per tile
-- and the bars are found by the PIXEL SHADER walking the view ray down
-- through the slab (Water.relief).  There is no crest for anything outside
-- that shader to stand on: asking for "the height of the wave under this
-- cell" would mean re-implementing the wave trains in Lua, evaluating them at
-- one point of a 16px ring, and bobbing the whole ring 0..5px a frame off a
-- number the shader is free to change.  The cartridge's ring does not bob.
-- So the honest answer is the SURFACE PLANE -- the quad the relief is carved
-- out of -- and the crests wash over the ring the same way they wash over
-- everything else drawn inside the water's footprint.
--
-- That plane is the cell's own drawn top.  Every cell a ripple can spawn on
-- is a `water` cell: the three rippling behaviours are 16, 20 and 22 (STATED,
-- Game.data.constants.gen3Ripple.behaviours, off MetatileBehavior_HasRipples)
-- and data/gen3_shapes.lua maps all three to class `water` (DERIVED, read out
-- of the shipped table).  ChunkMesher draws a water cell's sheet at that
-- class's own height -- -2 in the shipped data/voxel_heights.lua (STATED),
-- the recess TileShape sinks water into -- while `groundAt` deliberately
-- refuses to lower a walker for it ("a recessed class (water) still supports
-- whatever stands on it").  So the sheet is groundAt + the class recess, and
-- this asks the SAME TileShape lookup groundAt asks, at the same tx/ty, so
-- the two can never disagree about which shape the cell has.
--
-- Falls back to groundAt untouched wherever the cell is not `water` or the
-- profile does not recess it (recess >= 0) -- which is every Gen 1, Gen 2 and
-- Prism map, none of which can reach this function at all: no cartridge but
-- Gen 3 defines gen3Ripple, so `state.ripples` is never non-empty there.
--
-- KNOWN BOUND, stated rather than hidden: ChunkMesher's heightAt prefers a
-- terrace run's own height to the shape's where a water cell sits inside one,
-- and there the sheet is at run.h rather than run.h + recess.  This answers
-- the recessed figure, so such a ring lies up to |recess| = 2 world pixels
-- below its sheet.  Two pixels, under a surface whose own relief is five, on
-- a decal that writes no depth: it cannot be occluded by the error.
local function rippleSurfaceY(map, cellX, cellY)
  local gh = groundAt(map, cellX, cellY)
  if not (map and map.inBounds and map:inBounds(cellX, cellY)) then return gh end
  local okShapes, shapes = pcall(TileShape.forMap, map)
  if not (okShapes and type(shapes) == "table") then return gh end
  -- the same bottom-left collision tile groundAt reads (Map:cellTile)
  local tx, ty = cellX * 2, cellY * 2 + 1
  local okAt, s = pcall(TileShape.at, map, shapes, Gen3.tileAt(map, tx, ty),
                        tx, ty)
  if not (okAt and type(s) == "table") then return gh end
  if s.class ~= "water" then return gh end
  local recess = tonumber(s.h)
  if not recess or recess >= 0 then return gh end
  return gh + recess
end

-- ONE RING'S QUAD, lying in the XZ plane.
--
-- Sized and cut from the SpriteRenderer the flat path blits with, rather than
-- through SpriteBillboards: `tileW`/`tileH` and the row at `frame * tileH`
-- are exactly the box SpriteRenderer:drawFixedFrame hands LOVE, so the two
-- paths cannot come out showing different pictures whatever shape the ripple
-- sheet turns out to be.  (SpriteBillboards would also answer correctly for
-- the 16x16 sheet this is, but its walker branches -- big dolls, mirrored
-- half-strips, a 32-wide sheet that states no frame box -- are decisions
-- about CHARACTERS, and a field effect should not be routed through them.)
--
-- The half-pixel UV inset is the same 0.02 / 0.05 the character cards use, to
-- keep a neighbouring sheet row out of the ring's edge texels.
--
-- Memoised per sprite (weak-keyed, so a dropped SpriteRenderer takes its
-- meshes with it) and per frame: the cartridge's animation is a handful of
-- rows, so this builds at most that many quads for the whole session.
local rippleMeshes = setmetatable({}, { __mode = "k" })

local function rippleMesh(sprite, frame)
  local okTex, tex = pcall(sprite.resolveImage, sprite)
  if not (okTex and tex and tex.getDimensions) then return nil end
  local iw, ih = tex:getDimensions()
  if not (iw and ih and iw > 0 and ih > 0) then return nil end
  local tw = math.floor(tonumber(sprite.tileW) or 16)
  local th = math.floor(tonumber(sprite.tileH) or 16)
  if tw < 1 or th < 1 then return nil end
  local per = rippleMeshes[sprite]
  if per == nil then per = {}; rippleMeshes[sprite] = per end
  local key = frame .. "@" .. iw .. "x" .. ih
  local hit = per[key]
  if hit == nil then
    local fy = frame * th
    if fy + th > ih then fy = 0 end       -- same clamp drawFixedFrame's quad has
    local u0, u1 = 0.02 / iw, (math.min(tw, iw) - 0.02) / iw
    local v0, v1 = (fy + 0.05) / ih, (fy + th - 0.05) / ih
    -- built in the cards' own local space -- X right, Y up the sheet, Z zero
    -- -- and tipped onto the ground by the model matrix below, so the sheet's
    -- TOP ends up pointing north (away from the camera), which is how the
    -- flat game has it on screen.  Full shade (1): a ring is drawn art, not a
    -- lit face, exactly like a character card.
    local verts = {
      { 0, 0, 0, u0, v1, 1 }, { tw, 0, 0, u1, v1, 1 },
      { tw, th, 0, u1, v0, 1 }, { 0, th, 0, u0, v0, 1 },
    }
    local idx = {}
    Voxel3D.pushQuad(idx, 0)
    hit = Voxel3D.newMesh(verts, idx) or false
    per[key] = hit
  end
  if not hit then return nil end
  return hit, tex, tw, th
end

-- EVERY LIVE RING, AS GROUND GEOMETRY.
--
-- Called from drawScene between the water pass and the character pass; see
-- the call site for why that position is the fix.
--
-- Gen 3 only, without a cartridge test anywhere in here: `state.ripples` is
-- filled by OverworldState:updateRipples, every function of which returns
-- early unless Game.data.constants.gen3Ripple exists, and that constant is
-- written by the Gen 3 importer alone.  On Gen 1, Gen 2 and Prism the list is
-- nil and this returns on its first line.
--
-- Every engine call is guarded, because the ripple field effect is newer than
-- some caches this mod can be run against: a data set whose sprite table
-- predates SPRITE_G3_RIPPLE answers nil for the sheet and no rings are drawn,
-- which is what happened before any of this existed.
local function drawRipples(state)
  local rings = state and state.ripples
  if not (rings and #rings > 0) then return end
  local map = state.map
  if not map then return end
  if type(state.rippleSprite) ~= "function" then return end
  local okSprite, sprite = pcall(state.rippleSprite, state)
  if not (okSprite and sprite) then return end
  -- sprite sheets carry no wireframe and no glass, for the reasons drawCast
  -- argues about the characters: the grid turns a 16px drawing into a mesh,
  -- and the sheet's texcoords mean nothing to the tileset-shaped pane mask
  Voxel3D.glass(false)
  Voxel3D.seams(false)
  Voxel3D.beginDecal()
  for _, r in ipairs(rings) do
    local frame = 0
    if type(state.rippleFrame) == "function" then
      local okFrame, f = pcall(state.rippleFrame, state, r.clock)
      frame = (okFrame and tonumber(f)) or 0
    end
    local mesh, tex, tw, th = rippleMesh(sprite, frame)
    if mesh and r.px and r.py then
      -- the ring's own CENTRE picks the cell, not its top-left: spawnRipple
      -- lifts the 16px ring so it closes AROUND the feet rather than sitting
      -- under them, which leaves its top-left a few pixels north of the cell
      -- boundary while its middle stays inside the cell that was stepped on
      local cx = math.floor((r.px + tw * 0.5) / 16)
      local cy = math.floor((r.py + th * 0.5) / 16)
      -- SHADOW_EPS (0.25 world px, STATED): the mod's own already-calibrated
      -- "float above the ground to dodge z-fighting", borrowed rather than
      -- re-tuned.  It is needed because under the world curve drawWater runs
      -- a depth-writing prepass of the water surface, so a ring drawn exactly
      -- coplanar with the sheet fights it.  Lifting rather than pulling
      -- camera-ward keeps the ring's depth honest against the BRIDGE DECK a
      -- ring can reach under on Route 104 -- a quarter of a pixel cannot
      -- climb the ~18px from the sheet to the planks.
      local y = rippleSurfaceY(map, cx, cy) + Voxel3D.SHADOW_EPS
      -- local (x, y, 0) -> (x, 0, -y) under rotateX(-pi/2), so translating to
      -- the ring's SOUTH edge lands local y = 0 there and local y = th on its
      -- north edge: the quad covers exactly [px, px+tw] x [py, py+th], the
      -- same world rectangle SpriteRenderer:drawFixedFrame blits into
      local model = Mat4.mul(Mat4.translate(r.px, y, r.py + th),
                             Mat4.rotateX(-math.pi / 2))
      Voxel3D.draw(mesh, tex, model)
    end
  end
  Voxel3D.endDecal()
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

-- ------------------------------------------------- the thing you sit on
--
-- THE SURF BLOB IS GROUND GEOMETRY HERE, NOT A SECOND CARD.
--
-- In-game location: THE SEA OFF ROUTE 118, and every other stretch of Hoenn
-- water a SURF takes you onto.
--
-- Reported from play: "still missing the surf blob beneath the player when
-- surfing, add that and make sure its working as well -- this is with voxels
-- on in any mode, first and third person or not". It was missing outright:
-- the flat game draws it from `Player:drawSurfBlob` (src/world/Player.lua),
-- which `Player:draw` calls -- and with voxels on the player is a BILLBOARD
-- built by drawEntity, so `Player:draw` never runs and nothing in this file
-- had ever heard of the blob.
--
-- WHY A FLAT QUAD AND NOT A BILLBOARD, which is the other obvious answer.
-- The blob is a thing floating ON the water with the player sitting IN it,
-- and the deciding case is the one the report names: FIRST PERSON. There the
-- player's own card is deliberately left out -- "the eye is standing in it"
-- (drawCast, `hideMe`) -- so a blob billboarded at the same spot would be the
-- same lens-filling slab for the same reason, and the one thing you actually
-- want to see, the water immediately under you, is exactly what a card cannot
-- show. Laid flat it is there in every mode: you look down and the dome is
-- around you.
--
-- So this is drawRipples' shape, for drawRipples' reasons -- the ring under a
-- character is the closest thing in the mod to "a field effect lying on the
-- water" and it is already solved. Same decal pass (depth TESTED so a bridge
-- still hides it, never depth-WRITING so the cards drawn afterwards simply
-- paint over it and the player sits in his boat rather than under it), same
-- XZ quad, same half-pixel UV inset.
--
-- WHICH FRAME AND WHICH WAY ROUND is not decided here: `Player:surfBlobCard`
-- is, and this asks it. That function is the flat path's own arithmetic --
-- :drawSurfBlob is written in terms of it too -- so the two paths cannot show
-- different pictures. Three frames, and they are FACINGS (south / north /
-- west, east mirrored), not a film strip: MEASURED off this tree's own
-- data/generated/constants.lua, `gen3SurfBlob` is 32x32, `frames = 3`
-- (DERIVED). The blob's only motion over time is the surf BOB, and it gets
-- that for free below by standing on the player's own height.
--
-- The POSE facing, not `viewFacing`: a card is turned to face the eye because
-- it is a flat drawing pretending to be a solid, and this one really is lying
-- in the world with a real bearing. A first-person eye walking around the
-- south side of a surfer must see the blob's south side, not have it swing.
--
-- Gen 1 / Gen 2 / Prism draw nothing: `surfBlobCard` returns nil unless
-- `Game.data.constants.gen3SurfBlob` exists, and that constant is written by
-- the Gen 3 importer alone (RomExtractorGen3:surfBlob). There is no version
-- test in this file for the same reason drawRipples has none.
local blobMeshes = {}

-- ONE BLOB QUAD, lying in the XZ plane -- rippleMesh's geometry, cut from the
-- blob record's own stated frame box rather than from a SpriteRenderer, because
-- the blob is not an object-event graphic and has no SpriteRenderer to ask.
local function surfBlobMesh(tex, frame, fw, fh)
  if not (tex and tex.getDimensions) then return nil end
  local iw, ih = tex:getDimensions()
  if not (iw and ih and iw > 0 and ih > 0) then return nil end
  if fw < 1 or fh < 1 then return nil end
  local key = frame .. "@" .. fw .. "x" .. fh .. "@" .. iw .. "x" .. ih
  local hit = blobMeshes[key]
  if hit == nil then
    local fy = frame * fh
    if fy + fh > ih then fy = 0 end -- the clamp the flat path's quad has
    local u0, u1 = 0.02 / iw, (math.min(fw, iw) - 0.02) / iw
    local v0, v1 = (fy + 0.05) / ih, (fy + fh - 0.05) / ih
    -- built in the cards' own local space -- X right, Y up the sheet, Z zero
    -- -- and tipped onto the water by the model matrix below, so the sheet's
    -- TOP points north. Full shade (1): drawn art, like a card or a ring.
    local verts = {
      { 0, 0, 0, u0, v1, 1 }, { fw, 0, 0, u1, v1, 1 },
      { fw, fh, 0, u1, v0, 1 }, { 0, fh, 0, u0, v0, 1 },
    }
    local idx = {}
    Voxel3D.pushQuad(idx, 0)
    hit = Voxel3D.newMesh(verts, idx) or false
    blobMeshes[key] = hit
  end
  return hit or nil
end

-- `me` is the player's own entry in the pose list (posesOf), which is where
-- the HEIGHT comes from: `me.gh + me.lift` is the very number drawEntity
-- stands the player's card on, so the blob can never float away from the
-- player it is under, at any water level, on any terrace -- and the surf bob
-- (Player:pose, `bobTimer % 32`, one world pixel) rides in on `lift` and
-- bobs the blob with him, which is what SyncSurfblobPositionWithPlayer does
-- on the cartridge.
--
-- Deliberately NOT rippleSurfaceY: that answers the water SHEET's top, up to
-- two world pixels below the terrace top `groundAt` gives (see its comment),
-- and a decal drawn BELOW the sheet loses the depth test and disappears. The
-- player's own height is at or above the sheet, so it is the safe one as well
-- as the glued-to-him one.
--
-- SHADOW_EPS (0.25 world px, STATED) is the mod's own calibrated
-- "float clear of the surface to dodge z-fighting", borrowed from drawRipples
-- rather than re-tuned: under the world curve drawWater runs a depth-writing
-- prepass, so anything exactly coplanar with the sheet fights it.
local function drawSurfBlob(state, me)
  if not me then return end
  local player = state and state.player
  if not (player and player.surfBlobCard) then return end
  local okCard, blob, frame, mirror, offX, offY =
    pcall(player.surfBlobCard, player, me.facing)
  if not (okCard and type(blob) == "table") then return end
  local okTex, tex = pcall(require("src.render.Assets").image, blob.image)
  if not (okTex and tex) then return end
  local fw = math.floor(tonumber(blob.frameWidth) or 32)
  local fh = math.floor(tonumber(blob.frameHeight) or 32)
  local mesh = surfBlobMesh(tex, frame, fw, fh)
  if not mesh then return end
  local y = me.gh + (me.lift or 0) + Voxel3D.SHADOW_EPS
  -- the same world rectangle the flat path blits into: top-left at the
  -- player's own (px, py) plus surfBlobCard's offsets, fw x fh across. For
  -- Emerald's 32-square blob those offsets are -8, -8 (DERIVED), i.e. the
  -- player's 16px cell grown eight pixels on every side -- centred on the
  -- cell middle drawEntity anchors the player's card to (footAnchor = 8).
  local x0 = me.px + offX
  local z0 = me.py + offY
  -- local (x, y, 0) -> (x, 0, -y) under rotateX(-pi/2), so translating to the
  -- SOUTH edge lands local y = 0 there and local y = fh on the north edge
  local model = Mat4.mul(Mat4.translate(x0, y, z0 + fh),
                         Mat4.rotateX(-math.pi / 2))
  if mirror then
    -- east is west flipped (Player.lua BLOB_FRAME): mirror inside the quad's
    -- own box so it still covers exactly [x0, x0 + fw]
    model = Mat4.mul(model, Mat4.mul(Mat4.translate(fw, 0, 0),
                                     Mat4.scale(-1, 1, 1)))
  end
  Voxel3D.glass(false)
  Voxel3D.seams(false)
  Voxel3D.beginDecal()
  Voxel3D.draw(mesh, tex, model)
  Voxel3D.endDecal()
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

VoxelScene.drawSurfBlob = drawSurfBlob

-- ------- the planar mirror's plane
--
-- WHICH HEIGHT THE MIRRORED SCENE IS RENDERED FOR.
--
-- A planar reflection needs a PLANE and this mode's water is not one. Every
-- sheet lies at its own cell's drawn top -- the water class's recess over
-- whatever terrace the cell sits on -- so a map carries as many surfaces as
-- it has water at different elevations. MEASURED over every water-bearing
-- layout in Hoenn, off the mesher's own water sink: Petalburg City has 1,
-- Lilycove 3, Route 104 3 (61.3% at y=-2 and 38.3% at y=12, fourteen world
-- pixels apart), Route 119 6 and Route 120 5 (DERIVED).
--
-- A FRAME, though, very nearly has one. MEASURED over every camera window of
-- the flat game's own 240x160 across the region, the single most common
-- water height on screen covers 98.9% of the visible water on Route 104 --
-- the map this was reported from -- 93.3% in Lilycove, 92.3% on Route 119,
-- 85.8% on Route 120 and 100% on Petalburg and Route 110 (all DERIVED). So
-- the pass is rendered for the DOMINANT height in view, and the water shader
-- accepts it only on the fragments whose own sheet stands there
-- (Water.PLANE_TOL). The minority keeps the screen-space march and the sky
-- it already had: not a wrong reflection, the one it has always shown.
--
-- READ THROUGH rippleSurfaceY, deliberately and not by re-deriving it. That
-- function already answers "how high is the water sheet in this cell" for the
-- ripple rings, off the same TileShape lookup groundAt asks, and its header
-- argues at length why the SURFACE PLANE rather than the wave crest is the
-- honest answer -- the crests are carved by the pixel shader and there is no
-- geometry at one. Two functions answering that question two ways is two
-- answers that can drift; this is the same sentence twice.
--
-- SAMPLED ON A STRIDE rather than per cell. The mode is a diorama: water
-- comes in sheets, not in speckle, and the mode of a 4-cell lattice over the
-- view is the mode of the view. At the flat game's 240x160 that is about 40
-- lookups a frame against 150 cells, and it is memoised on the view rectangle
-- besides, so a standing camera pays once.
--
-- Gen 1, Gen 2 and Prism reach this exactly as Gen 3 does and get the same
-- answer from the same lookup: `isWaterCell` is the engine's, rippleSurfaceY
-- falls back to groundAt untouched wherever the cell is not a recessed water
-- class, and the row that calls any of this is OFF by default everywhere.
local PLANE_STRIDE = 4
local planeCache = setmetatable({}, { __mode = "k" })

local function waterPlane(map, cx, cy, vw, vh)
  if not (map and map.inBounds and vw and vh) then return nil end
  -- the view rectangle in CELLS, generously: the diorama camera sees past
  -- the flat game's own window, and a plane chosen off too small a sample is
  -- the wrong plane the moment the camera pans
  local halfW = math.floor((vw / 16) * 0.75) + 2
  local halfH = math.floor((vh / 16) * 0.75) + 2
  local ccx, ccy = math.floor(cx / 16), math.floor(cy / 16)
  local key = ccx .. "," .. ccy .. "," .. halfW .. "," .. halfH
  local hit = planeCache[map]
  if hit and hit.key == key then return hit.y end
  local counts, best, bestN = {}, nil, 0
  for gy = ccy - halfH, ccy + halfH, PLANE_STRIDE do
    for gx = ccx - halfW, ccx + halfW, PLANE_STRIDE do
      local okW, isW = pcall(map.isWaterCell, map, gx, gy)
      if okW and isW then
        local y = rippleSurfaceY(map, gx, gy)
        if y then
          local n = (counts[y] or 0) + 1
          counts[y] = n
          -- ties go to the LOWER sheet, which is the open water rather than
          -- a pond on a terrace above it: a tie means the two are equally
          -- present and the lower one is the one a shoreline camera is
          -- looking across. Deterministic either way, which matters more
          -- than which way -- a plane that flickers between two heights
          -- flickers the whole reflection with it.
          if n > bestN or (n == bestN and best and y < best) then
            best, bestN = y, n
          end
        end
      end
    end
  end
  planeCache[map] = { key = key, y = best }
  return best
end

-- THE MIRRORED SCENE ITSELF.
--
-- WHAT GOES IN, and what does not. Everything here is drawn a SECOND time,
-- so every entry is a draw call bought with a reason:
--
--   THE TERRAIN, and every neighbour's. The shoreline, the cliffs, the
--   buildings and the bridge deck are the mass of what a lake reflects, and
--   they are one mesh per map -- the cheapest thing in the frame per pixel
--   of reflection it buys. MeshBounds still culls an off-screen neighbour
--   inside Voxel3D.draw, and a mirrored neighbour is off screen exactly when
--   the upright one is.
--
--   THE GRASS AND THE FLOWERS, one mesh each per map. A grassy bank that
--   reflects as bare soil is the reflection saying the bank is not there.
--
--   THE CAST, through the SAME callback the screen-space mirror is given.
--   This is the entire reason the pass exists (see Water.planarLevel), and
--   routing it through one function is the same call drawCast already makes
--   for itself: two copies of a draw are two copies that can diverge.
--
-- ...AND WHAT IS DELIBERATELY LEFT OUT:
--
--   THE RIPPLE RINGS. A ring lies flat IN the plane, so mirrored it lands on
--   the screen pixels it already occupies -- and it is drawn there for real,
--   after the water, by drawRipples. The reflection of it would be exactly
--   underneath its own opaque draw and invisible. drawRipples' own header
--   expects a planar pass to "get these for free"; measured against what the
--   frame would show, free is also worthless here, and a draw call that
--   cannot change a pixel is not one this pass should spend. (It is the same
--   conclusion the screen-space mirror reached by a different route: a disc
--   lying flat on a mirror is doubled onto itself.)
--
--   THE WATER ITSELF. There is nothing to reflect a mirror in, and the
--   surface is exactly at the clip plane, where it would z-fight its own
--   flipped copy.
--
--   THE PLAYER'S SILHOUETTE. It is a trick played on the camera -- "the
--   world is in front of the player" -- and the mirror is not the camera.
--
-- Returns the mirror texture, or nil, in which case the water shader is sent
-- `planarOn` 0 and draws the reflection it drew before this existed.
local function drawPlanar(state, terrain, nbMesh, atlasFor, cast,
                          cx, cy, vw, vh)
  if not Water.reflectPlanar() then return nil, nil end
  if not Voxel3D.planarReady() then return nil, nil end
  local map = state and state.map
  local planeY = map and waterPlane(map, cx, cy, vw, vh)
  -- No water anywhere in view: nothing would sample the texture, so the
  -- whole pass is skipped and the frame costs exactly what it always did.
  -- This is also what makes the row free on a map with no lake in it.
  if not planeY then return nil, nil end
  local tP = Perf.now()
  -- one counter per frame the pass actually runs, so a measured run can tell
  -- "the row is on" from "the row is on and the frame is paying for it" --
  -- the two are different on any map with no water in view (see above).
  -- Dark unless DS_PERF is set, like everything else in Perf.
  Perf.count("water.planar")
  local tex = Voxel3D.beginPlanar(planeY, function()
    Voxel3D.draw(terrain, atlasFor(state.map), nil)
    for i, nb in ipairs(state.neighbors or {}) do
      Voxel3D.draw(nbMesh[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
    end
    -- the bank the water laps at. No camera-ward pull: the pull is a depth
    -- bias aimed at the FRAME's own buffer, to settle grass against the feet
    -- standing in it, and in here there are no feet to settle against -- the
    -- mirror has its own depth buffer and the only question it asks is which
    -- mirrored thing is in front of which.
    Voxel3D.draw(ChunkMesher.grass(state.map), atlasFor(state.map), nil)
    Voxel3D.draw(ChunkMesher.flowers(state.map), atlasFor(state.map), nil)
    for _, nb in ipairs(state.neighbors or {}) do
      local m = Mat4.translate(nb.ox, 0, nb.oy)
      Voxel3D.draw(ChunkMesher.grass(nb.map), atlasFor(nb.map), m)
      Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map), m)
    end
    if cast then cast() end
  end)
  Voxel3D.endPlanar()
  Perf.add("VoxelScene.drawPlanar", tP)
  return tex, planeY
end

-- ------- the water pass
--
-- Between the terrain and everything that stands on it, because water is a
-- MIRROR and a mirror can only reflect what is already down: the ground, the
-- shoreline, the trees and buildings behind it, and the sky the frame opened
-- with.
--
-- THE CAST IS THE AWKWARD ONE, and it is settled by drawing it twice. Gen 1
-- draws people over the world and water is world, so a surfing player has to
-- composite OVER the water they are sitting on -- which puts them after it,
-- and a reflection can only hold what came before it. So `cast` is painted
-- into the reflection copy alone (Voxel3D.beginWater), where it is in the
-- picture the water reflects and not yet in the picture the water is drawn
-- into. Both draws go through drawCast, so they cannot come out different.
--
-- The ray march finds them the honest way round: a sprite is not in the
-- DEPTH buffer at that point, so a ray aimed at one passes through to the
-- terrain standing behind it and reads the copy there -- where the sprite is
-- already painted. The reflection lands a hair off the sprite's own depth
-- and exactly on its colour, which at a lake's worth of ripple is the same
-- picture.
--
-- `draws` is a list of { mesh, texture, model }. Nothing is a special case:
-- with the row OFF, no depth texture to read, or a shader that would not
-- build, the same meshes go through the ordinary scene shader and come out
-- as the flat animated water this mode always drew.
-- The overworld's alone: the staged battle draws its water plain, always --
-- its placed camera reads this pass wrong, and a stage set wants painted
-- water anyway (see BattleScene, where the choice is argued).
-- ------- and why the flat draw happens FIRST while the world is curved
--
-- The reflective pass writes no depth -- it cannot, the depth canvas is
-- detached for the length of it so the shader can READ it -- and it does its
-- own depth test against that texture instead. That test asks whether
-- something opaque is in front, and it answers correctly for every case but
-- one: WATER IN FRONT OF WATER. Nothing puts water in the depth buffer, so
-- no lake can hide another, and the pass simply paints them in mesh order.
--
-- On a flat world that never matters: every surface lies in the one plane
-- at its own recessed height, and a farther sheet always lands farther down
-- the screen. THE WORLD CURVE ENDS THAT. The bend drops the world by the
-- square of its distance, so the far side of the map swings down and back
-- up into the near field of view -- and a sheet of sea a hundred and fifty
-- tiles away, drawn later in the same mesh, paints straight over the pond
-- at the player's feet. Not a reflection of the far shore: the far shore
-- itself, rasterised on top of the water in front of you.
--
-- So WHILE THE CURVE IS ON, the meshes go down flat first, through the
-- ordinary scene shader with depth writes on, and the reflective pass draws
-- over the top of what survived: the depth buffer now holds the water
-- surface, so the pass's own test throws the far sheet away, and the
-- reflection COPY holds it too, so a ray grazing another part of the lake
-- reads water rather than the void behind it.
--
-- With the curve OFF the prepass is not just unnecessary, it is a LIABILITY,
-- and it stays off -- the reflective pass tests only against terrain, as it
-- always did. Painting the surface into the depth texture turns the pass's
-- test into a comparison of the surface against ITSELF, which asks the two
-- rasterisations to agree to within interpolation error -- and on mobile
-- GPUs they don't reliably (that fight is what put the Android port back on
-- flat water). Confined to the curve there is no regression to reach: the
-- flat world never had the far-shore bug in the first place.
function VoxelScene.drawWater(draws, cast, planar, planarY)
  local tW = Perf.now()
  -- prepass only under the bend; see the header
  local curved = (Voxel3D.curveK or 0) > 0
  if curved then
    for _, d in ipairs(draws) do
      Voxel3D.draw(d[1], d[2], d[3])
    end
  end
  local plain = not curved
  if Water.enabled() and Voxel3D.depthReadable() then
    -- `cast` only where something will actually LOOK at the mirror. Below
    -- FULL the shader's `rays` is 0 and it never samples reflectTex at all,
    -- so the cards would be drawn a second time into a texture no pass
    -- reads -- which at the BALANCED tier, where the ceiling holds WATER at
    -- SKY, was every frame in Lilycove paying for a hundred and thirty-odd
    -- draws nobody looked at (see Water.castLevel). With the WATER SPRITES
    -- row ON at FULL this is exactly the `cast` it always was, and the
    -- frame is the frame it always drew.
    local mirror, depth = Voxel3D.beginWater(Water.reflectCast() and cast
                                             or nil)
    local w, h = Voxel3D.size()
    local ok = mirror and depth and Water.begin({
      reflect = mirror, depth = depth,
      vp = Voxel3D.vp, eye = Voxel3D.eye, curve = { Voxel3D.curveX or 0,
                                                    Voxel3D.curveZ or 0,
                                                    Voxel3D.curveK or 0 },
      screen = { w, h }, cell = Voxel3D.cell, fov = Voxel3D.fovY,
      skyEdge = Voxel3D.skyEdge, grid = VoxelGrid.enabled(),
      lookFlat = Voxel3D.lookFlat, descent = Voxel3D.descent,
      -- the mirrored scene, already rendered and already released from its
      -- canvas (see drawPlanar). nil is the answer on every frame the row is
      -- off, the tier capped it, there is no water in view, or the driver
      -- would not make the pair -- and `planarOn` 0 is what the shader is
      -- sent then.
      planar = planar, planarY = planarY,
    })
    if ok then
      for _, d in ipairs(draws) do
        Water.draw(d[1], d[2], d[3])
      end
      Water.finish()
      plain = false
    end
    -- Unconditionally, and OUTSIDE the success branch: beginWater unbinds
    -- the shader and the depth mode BEFORE it can discover it cannot go on,
    -- so a frame that bails halfway through has to be put back together
    -- exactly like one that succeeded -- otherwise every pass after it runs
    -- with no shader and no depth test.
    Voxel3D.endWater()
  end
  -- the fallback flat draw -- unless the curve's prepass already put the
  -- same meshes down, in which case a bailed frame is already whole
  if plain then
    for _, d in ipairs(draws) do
      Voxel3D.draw(d[1], d[2], d[3])
    end
  end
  Perf.add("VoxelScene.drawWater", tW)
end

-- How many STALE frames the sun has seen, and which of them it last drew
-- on: the rate limiter's whole state (see castShadows). Counted in stale
-- frames rather than in rendered ones on purpose -- a scene where nothing
-- moves at all does not want a redraw every third frame, it wants none.
local shadowStale, shadowLastCast = 0, -1000
local shadowLastStatic = nil

-- A stamp of everything the sun pass depends on. Nothing in it moving
-- means the shadow map it produced last frame is still exactly right, and
-- redrawing the whole world from the sun would buy nothing -- which is
-- most of a dialog, a menu, or any moment standing still.
local sigBuf = {}
local sigN = 0
local function sigPut(v)
  sigN = sigN + 1
  sigBuf[sigN] = v
end

-- THE HALF OF THE STAMP THAT IS NOT THE MOVING CAST.
--
-- Split out of shadowSignature below (which still appends the cast to it,
-- so the full stamp is exactly the terms it always carried) because the two
-- halves fail in completely different ways when they go stale. If the
-- CAMERA has moved, or the view size has, or the sun has swung, or a
-- neighbour's mesh has arrived, then the map that exists was fitted to a
-- different frustum and reusing it does not make a shadow late -- it makes
-- it WRONG, in the wrong place, on the wrong geometry. If only the cast has
-- moved, the map is still fitted correctly and every static shadow in it is
-- still exactly right; the only thing out of date is where a walking person
-- put their own shadow, and that is an error of a pixel or two that a tier
-- is allowed to trade for half the frame (see castShadows).
local function shadowStaticTerms(terrain, nbMesh, cx, cy, vw, vh)
  local put = sigPut
  -- quarter-pixel camera granularity: the light frustum is snapped to
  -- whole texels anyway, each a third of a world pixel
  put(math.floor(cx * 4))
  put(math.floor(cy * 4))
  -- the view size and the camera PITCH are both what the light frustum is
  -- fitted to (a lower camera sees further north, so the box grows), so a
  -- zoom step, a window resize or a rung change invalidates the map even
  -- standing perfectly still
  put(vw); put(vh)
  put(math.floor((V.require("VoxelState").angle or 0) * 512))
  -- the sun itself: the cycle swings the shear as the clock runs, and a map
  -- lit from somewhere new must be redrawn from there too. Quantised by the
  -- rig's own step (DayNight.rigTime), so a running cycle redraws the map a
  -- few times a minute rather than every frame.
  put(math.floor(ShadowMap.KX * 128))
  put(math.floor(ShadowMap.KZ * 128))
  -- and the first-person head: the box is fitted around wherever it looks
  -- and the sprite cards swap frames as it circles them, so a turn on the
  -- spot re-fits and redraws exactly like a camera move ("" outside 1ST)
  put(FirstPerson.signature())
  put(tostring(terrain))
  for i = 1, #nbMesh do put(tostring(nbMesh[i])) end
end

-- The static half alone, for the rate limiter in castShadows. Shares the
-- one buffer with the full stamp and is only ever called after it, so the
-- string the full stamp already produced has been copied out by concat.
local function shadowStaticSignature(terrain, nbMesh, cx, cy, vw, vh)
  sigN = 0
  shadowStaticTerms(terrain, nbMesh, cx, cy, vw, vh)
  for i = sigN + 1, #sigBuf do sigBuf[i] = nil end
  return table.concat(sigBuf, ",")
end

local function shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  sigN = 0
  shadowStaticTerms(terrain, nbMesh, cx, cy, vw, vh)
  local put = sigPut
  for _, p in ipairs(posed) do
    put(p.sprite.def.image)
    put(p.px); put(p.py); put(p.gh); put(p.lift or 0)
    put(p.facing); put(p.phase); put(p.flip and 1 or 0)
  end
  for i = sigN + 1, #sigBuf do sigBuf[i] = nil end
  return table.concat(sigBuf, ",")
end

-- The sun pass: render the scene once from the light, so the main pass can
-- ask any fragment whether the sun reached it. Every caster the main pass
-- draws goes in -- the terrain mesh, which is where buildings, trees,
-- ledges, signs and every prop live, plus one UPRIGHT card per character
-- (Voxel3D.casterMatrix; the leaning slab is a trick for the camera, not
-- for the sun) -- so shadows land on walls, roofs, ledges and passing NPCs
-- as readily as on the floor.
--
-- Runs BEFORE Voxel3D.beginScene, because canvases do not nest. Grass is
-- left out on purpose: thousands of tufts would cast a speckle no bigger
-- than the pixels it lands on, at the cost of the mesh being drawn twice.
local function castShadows(state, terrain, nbMesh, posed, cx, cy, vw, vh,
                           atlasFor, water, nbWater, battleCards, battleToken)
  if not ShadowMap.available() then return end
  local sig = shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  -- a staged fight's pics move every frame the animation does, and the sun
  -- has to follow them (VR frames only; see render)
  if battleToken then sig = sig .. "|btl" .. tostring(battleToken) end
  if not ShadowMap.stale(sig) then return end

  -- THE SUN DOES NOT HAVE TO FOLLOW EVERY FOOTSTEP.
  --
  -- The stamp above is honest and it is also why this pass runs on every
  -- single frame: it stales on any caster moving, and in a town or a wood
  -- somebody is always mid-step. Measured standing still in Petalburg
  -- Woods with nothing left to build: 202 sun passes in 202 rendered
  -- frames, 53% of VoxelScene.render, to re-record a terrain mesh that had
  -- not changed by one vertex.
  --
  -- So BALANCED rate-limits the CAST half and only the cast half. The
  -- static half (camera, view, sun angle, first-person head, the meshes
  -- themselves) still forces a redraw on the frame it changes, because a
  -- map fitted to last frame's frustum is a wrong shadow rather than a late
  -- one -- see shadowStaticTerms. What is delayed is strictly "somebody
  -- took a step", and at the shipped rate of 3 the worst case is a walker's
  -- own shadow two frames behind their feet, which at walking pace is under
  -- two world pixels.
  --
  -- nil at HIGH -- the branch is skipped entirely and this function behaves
  -- exactly as it did, redraw for redraw.
  local hz = Tier.caps().shadowHz
  if hz and hz > 1 then
    local st = shadowStaticSignature(terrain, nbMesh, cx, cy, vw, vh)
    shadowStale = shadowStale + 1
    if st == shadowLastStatic and (shadowStale - shadowLastCast) < hz then
      Perf.count("shadow.throttled")
      return
    end
    shadowLastStatic, shadowLastCast = st, shadowStale
  end

  Perf.count("shadow.cast")
  local tSun = Perf.now()
  if not ShadowMap.begin(cx, cy, vw, vh) then return end

  ShadowMap.draw(terrain, atlasFor(state.map), nil)
  for i, nb in ipairs(state.neighbors or {}) do
    ShadowMap.draw(nbMesh[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
  end
  -- The water surface, which the terrain mesh no longer carries (it is its
  -- own reflective pass now -- see Water). The sun still has to see it, or
  -- the map the light records has a hole at every lake and the frustum's
  -- far plane answers for the surface a shoreline tree's shadow falls on.
  ShadowMap.draw(water, atlasFor(state.map), nil)
  for i, nb in ipairs(state.neighbors or {}) do
    ShadowMap.draw(nbWater and nbWater[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
  end
  -- flower billboards live outside the terrain mesh (they draw after the
  -- characters, pulled -- see render), but the sun still sees them: a
  -- handful of cutouts per meadow, unlike the grass left out below.
  -- Every thin card from here down is SNUGGED toward the sun along its own
  -- ray (ShadowMap.snug) so its shadow keeps contact with its feet instead
  -- of starting a bias-width away.
  ShadowMap.draw(ChunkMesher.flowers(state.map), atlasFor(state.map),
                 ShadowMap.snug(nil))
  for _, nb in ipairs(state.neighbors or {}) do
    ShadowMap.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
  end
  -- From here down it is the CAST, marked as such in the map (see
  -- ShadowMap.sprites) so water can decline them: everything the world casts
  -- still shades a lake, a silhouette of somebody standing beside it does
  -- not. Ground, roofs and the characters themselves take them as before.
  ShadowMap.sprites(true)
  -- authored figures cast too, for the same reason the flowers do: a
  -- handful of cards per map, and a person with no shadow reads as pasted on
  eachFigure(state.map, 0, 0, function(mesh, _, caster)
    ShadowMap.draw(mesh, atlasFor(state.map), ShadowMap.snug(caster))
  end)
  for _, nb in ipairs(state.neighbors or {}) do
    eachFigure(nb.map, nb.ox, nb.oy, function(mesh, _, caster)
      ShadowMap.draw(mesh, atlasFor(nb.map), ShadowMap.snug(caster))
    end)
  end
  for _, p in ipairs(posed) do
    local def = p.sprite.def
    -- viewFacing, exactly as the camera draw picks it (see viewFacing for
    -- why the two passes must agree): in first person the sun's card
    -- swaps frame as the eye circles, which costs a redraw the signature
    -- already charges for (FirstPerson.signature) and keeps a card from
    -- fringing against a mirror-flipped record of itself
    local frame, mirror = frameFor(def, viewFacing(p), p.phase, p.flip, p.frame)
    local mesh = SpriteBillboards.shadowQuad(def, frame)
    if mesh then
      -- the same pair the camera draw uses, or the sun files a wide card
      -- half a width away from where the lit one asks about it (see
      -- drawEntity, and SpriteBillboards.footAnchor for the rule)
      local sHalf = (SpriteBillboards.halfWidth
                     and SpriteBillboards.halfWidth(def)) or 8
      local sAnchor = SpriteBillboards.footAnchor
                      and SpriteBillboards.footAnchor(def)
      ShadowMap.draw(mesh, p.sprite:resolveImage(),
                     ShadowMap.snug(
                       Voxel3D.casterMatrix(p.px, p.py, p.gh + (p.lift or 0),
                                            mirror, sAnchor and sHalf,
                                            sAnchor)))
    end
  end
  -- a staged fight's mons (VR frames only): the same cards the eye pass
  -- stands on the arena, snugged like every thin card, marked as the cast
  -- so the water can decline them like everybody else's silhouette
  for _, card in ipairs(battleCards or {}) do
    ShadowMap.draw(BattleBillboard.mesh(), card.tex, ShadowMap.snug(card.model))
  end
  ShadowMap.sprites(false)

  ShadowMap.finish(sig)
  Perf.add("VoxelScene.castShadows", tSun)
end

-- Render the world. Without `eyes`, one frame into one canvas -- the flat
-- path every rung has always taken. With `eyes` -- a list of
-- { camera, w, h, slot, adopt } records, plus optional cx/cy for the
-- scene centre -- the same frame is drawn once per entry and the list of
-- canvases comes back: the VR path, two eyes over one shared shadow map,
-- pose capture and glint step.
-- one line per map, so a flat world explains itself without flooding
local reportedNoMesh = {}

function VoxelScene.render(state, w, h, vw, vh, paletteFor, eyes)
  local tR = Perf.now()
  -- With nothing cached at all (the first frame of a fresh toggle),
  -- return nil: the engine keeps the 2D path for the frame and
  -- Voxel.ready holds the camera tween at flat, so the switch waits
  -- invisibly instead of freezing or tilting an empty stage.
  local terrain, nbMesh, water, nbWater = VoxelScene.prefetch(state)
  if not terrain then
    -- SAY WHY, ONCE.  Returning nil here is indistinguishable from "the mod
    -- chose not to draw": the engine keeps the flat path and the player sees
    -- the voxel setting do nothing at all, with an empty log.  On the first
    -- frame of a toggle that is correct and temporary; when a build has
    -- FAILED it is permanent, because a failed slot caches `false` and is
    -- never retried.  Those two need telling apart from outside.
    local map = state and state.map
    local id = map and map.id
    if id and not reportedNoMesh[id] then
      reportedNoMesh[id] = true
      local why = ChunkMesher.buildFailure and ChunkMesher.buildFailure(id)
      pcall(function()
        local Logger = require("src.core.Logger")
        if why then
          Logger.warn("voxel world: no mesh for %s and the build FAILED -- "
                      .. "the world will stay flat on this map: %s",
                      tostring(id), tostring(why))
        else
          Logger.info("voxel world: no mesh for %s yet (queued) -- flat for "
                      .. "now%s", tostring(id),
                      Gen3.status and (" | " .. tostring(Gen3.status(map) or ""))
                      or "")
        end
      end)
    end
    return nil
  end

  local cam = state.camera
  local cx, cy = cam.x + vw / 2, cam.y + vh / 2

  -- the hour's light, before anything is cast or drawn: point the shared
  -- rig at the clock (or at noon, indoors -- a cave at midnight is exactly
  -- as dark as a cave at noon) and set the tint the scene shader multiplies
  -- every surface by. A CANOPY map (Viridian Forest) is the case between:
  -- the rig stays at noon and no sky is painted, but the hour's tint still
  -- falls through the leaves -- night reaches a forest floor.
  local outdoor = state.map.def and Map.isOutdoor(state.map.def) or false
  DayNight.applyRig(outdoor)
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(state.map))
  -- and the window glass: the tileset's own panes (found in its art --
  -- GlassMask), lit after dark. Outdoors only, like everything the clock
  -- touches, which also keeps any pane-shaped art in an interior tileset
  -- from picking up a glint.
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(state.map.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  local g = VoxelScene.glintStep(glint, cx, cy)
  Voxel3D.glassPhase, Voxel3D.glassGlint = g.phase, g.amp

  local function atlasFor(map)
    return TerrainAtlas.forMap(map, modeColors(paletteFor, map))
  end

  -- sprite palettes only exist in the SGB modes; under RED++ the OBP bake
  -- inside sprite:resolveImage() already colors the sheet
  local function spriteColors(map)
    if PaletteFX.usesGbcPack() then return nil end
    return modeColors(paletteFor, map)
  end

  local posed, me = posesOf(state, spriteColors)

  -- THE CAMERA RIDES WITH THE PLAYER, IN Y AS WELL AS IN X AND Z.
  --
  -- The orbit is centred on the view centre the flat renderer already
  -- computed, and it used to look at the world datum -- Y = 0 -- however
  -- high the player had climbed.  On a flat town that is invisible; on
  -- Sootopolis, Mossdeep or Lavaridge it is not: step up a flight and the
  -- terrace rises under you while the view stays pinned to the water
  -- level, so the player slides up the frame and the shot fills with the
  -- ground behind them.  The 2D camera follows the player exactly and this
  -- one now does too, lifting eye and focus together so the framing is
  -- unchanged and only its datum moves.
  --
  -- The CELL's height, not the sprite's: `gh` is what the walker is
  -- standing on, while `py` arcs through a ledge hop and bobs on a surf.
  -- Following the sprite would make the whole world jump with every hop.
  -- ...eased, not snapped.  A step up is a whole course in one frame -- the
  -- cell's height changes the instant the walk starts -- and moving the
  -- camera that far in one frame throws the entire world down the screen.
  -- A short exponential settle (about a twelfth of a second) reads as the
  -- camera keeping up rather than as a cut, and is over before the step is.
  -- A map change snaps: gliding a storey on arrival is a warp that looks
  -- like a fall.
  local targetY = (me and me.gh) or 0
  local mapId = state.map and state.map.id
  local dtc = (love.timer and love.timer.getDelta and love.timer.getDelta())
              or (1 / 60)
  if dtc ~= dtc or dtc < 0 then dtc = 1 / 60 end
  if dtc > 0.1 then dtc = 0.1 end
  if groundFollow.map ~= mapId or groundFollow.y == nil then
    groundFollow.map, groundFollow.y = mapId, targetY
  elseif math.abs(targetY - groundFollow.y) < 0.25 then
    groundFollow.y = targetY
  else
    groundFollow.y = groundFollow.y
                     + (targetY - groundFollow.y) * (1 - math.exp(-dtc * 14))
  end
  Voxel3D.groundY = groundFollow.y

  -- The first-person rig, built (or blended) for this frame and handed to
  -- Voxel3D BEFORE either pass runs: the sun's box is fitted around this
  -- camera, and every card matrix asks it which way to turn. With the
  -- blend fully out the call clears the placed camera and the orbit is
  -- exactly what it always was. The scene centre it returns walks from
  -- the orbit's view centre into the head, so the curve's focus and the
  -- depth reference follow the camera actually in charge.
  --
  -- A VR frame skips all of it: the caller brought its own cameras, and
  -- its own idea of the scene centre with them.
  if not eyes then
    local fpRig, fpCx, fpCy = FirstPerson.frame(me, cx, cy, vw, vh)
    if fpRig then cx, cy = fpCx, fpCy end
  elseif eyes.cx then
    cx, cy = eyes.cx, eyes.cy
  end

  -- A staged fight, seen by the VR eyes: the flat screen draws the battle
  -- SCREEN while one is up (this pass never runs), but the headset keeps
  -- looking at the world, so the world had better have the fight on it.
  -- Fetched per frame for the sun, and again per EYE in drawScene, because
  -- the cards yaw toward whichever eye is asking.
  local battleCards, battleTex, battleToken = nil, nil, nil
  if eyes then
    local okB, cards, tex, token = pcall(function()
      return V.require("OverworldBattle").worldCards()
    end)
    if okB and cards then
      battleCards, battleTex, battleToken = cards, tex, token
    end
  end

  -- The sun's box, pushed along the first-person look so it covers the
  -- ground THIS camera sees (a no-op at blend zero): the orbit's fit
  -- reaches far north and barely south, which is right for every rung
  -- but a head free to face south.
  local shCx, shCy = FirstPerson.shadowCenter(cx, cy, vh)
  castShadows(state, terrain, nbMesh, posed, shCx, shCy, vw, vh, atlasFor,
              water, nbWater, battleCards, battleToken)

  -- Everything between beginScene and endScene, as one function: the flat
  -- path runs it once, a VR frame runs it once PER EYE -- same posed
  -- list, same shadow map, same glint, so the two eyes can never disagree
  -- about anything but their viewpoint.
  local function drawScene()

  Voxel3D.draw(terrain, atlasFor(state.map), nil)
  for i, nb in ipairs(state.neighbors or {}) do
    Voxel3D.draw(nbMesh[i], atlasFor(nb.map),
                 Mat4.translate(nb.ox, 0, nb.oy))
  end

  -- Without a shadow map (headless, or a driver that could not make the
  -- canvas) the old flat decals stand in: ground-only, characters only,
  -- but better than a world with nothing under anybody. They go down
  -- first, as decals the characters then stand over -- depth-tested
  -- against the terrain just drawn (a shadow behind a building stays
  -- hidden) but never depth-writing, so the grass pass at the end of the
  -- frame still wins its feet-overdraw fights.
  if not Voxel3D.shadowsActive() then
    Voxel3D.beginShadows()
    for _, p in ipairs(posed) do
      -- the decal is the card squashed onto the ground, so it is the
      -- SAME frame the lit card and the sun's record use (see statedFrame);
      -- `stated` rides after `lift` and is nil for every card that names no
      -- row of its own
      drawShadow(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,
                 p.lift, p.frame)
    end
    Voxel3D.endShadows()
  end

  -- ------- the staged fight's mons, as a function
  --
  -- Standing on their arena cells in THIS eye's view (VR frames only;
  -- battleTex is nil otherwise). Rebuilt per eye because the cards yaw
  -- toward the eye that is looking. No wireframe and no glass on them for
  -- the reasons BattleBillboard and the battle pass each argue: the cards
  -- are not on the voxel grid, and their texcoords mean nothing to the
  -- tileset's pane mask. The hit flash rides the same flatten the battle
  -- pass uses, held short of solid.
  --
  -- A FUNCTION, AND DEFINED UP HERE, because it is drawn TWICE -- once into
  -- the water's reflection copy just below, and once into the frame after
  -- the cast. It used to be neither: it ran once, inline, after the water,
  -- so the mons were the one part of the cast with nothing under them on a
  -- lake. Water's own header has listed "a staged battle's two Pokemon"
  -- among what the mirror holds since the pass was written; this is the
  -- code catching up with it. One function for the same reason drawCast is
  -- one function: two copies of a draw are two copies that can diverge.
  --
  -- Asking OverworldBattle for the cards twice in one eye is safe and
  -- deliberate: monCards is a pure function of the arena, the live textures
  -- and Voxel3D.eye, and none of the three moves between the two calls
  -- inside a single eye's drawScene. It advances no timer -- unlike pose(),
  -- which is why the CAST is posed once and this is not.
  local function drawBattleCards()
    if not battleTex then return end
    local okB, cards = pcall(function()
      return V.require("OverworldBattle").worldCards()
    end)
    if not (okB and cards) then return end
    local BattleScene = V.require("BattleScene")
    Voxel3D.glass(false)
    Voxel3D.seams(false)
    if battleTex.flash then
      Voxel3D.flatten(BattleScene.FLASH_COLOR, BattleScene.FLASH_STRENGTH)
    end
    for _, card in ipairs(cards) do
      Voxel3D.draw(BattleBillboard.mesh(), card.tex, card.model,
                   BattleBillboard.PULL)
    end
    if battleTex.flash then Voxel3D.flatten(nil) end
    -- and the MOVE ANIMATIONS, standing on the same arena: the engine's own
    -- effects layer on the plane through both cells (BattleScene.fxCard),
    -- pulled a little harder than the mons so a burst plays over the card
    -- it is bursting on
    local okA, fxTex, fxModel = pcall(function()
      return V.require("OverworldBattle").worldAnim()
    end)
    if okA and fxTex and fxModel then
      Voxel3D.draw(BattleBillboard.mesh(), fxTex, fxModel,
                   BattleBillboard.PULL + 6)
    end
    Voxel3D.seams(true)
    Voxel3D.glass(true)
  end

  -- and the water over the top of it, reflecting everything just drawn plus
  -- the sky the frame opened with (see drawWater).
  --
  -- After the fallback decals deliberately: those are the stand-in drop
  -- shadows for a frame with no shadow map, they write no depth, and a
  -- lake would otherwise wear one as a black smear. Water covers them,
  -- which is the same answer the shadow map's own pass gives (see
  -- ShadowMap.sprites) -- people do not shadow water either way.
  local waterDraws = {}
  if water then
    waterDraws[#waterDraws + 1] = { water, atlasFor(state.map), nil }
  end
  for i, nb in ipairs(state.neighbors or {}) do
    if nbWater and nbWater[i] then
      waterDraws[#waterDraws + 1] = { nbWater[i], atlasFor(nb.map),
                                      Mat4.translate(nb.ox, 0, nb.oy) }
    end
  end
  if #waterDraws > 0 then
    -- ONE `cast` CLOSURE FOR BOTH MIRRORS, built once here. The
    -- screen-space copy needs it for colour and the planar pass needs it for
    -- geometry, and they must be the same crowd in the same poses or the two
    -- halves of one reflection disagree about who is standing there.
    local castOnce = function()
      drawCast(state, posed, atlasFor)
      drawBattleCards()
    end
    -- THE MIRRORED SCENE FIRST, because drawWater is about to take the
    -- frame's own canvas apart -- beginWater detaches the depth texture so
    -- the march can read it -- and a whole second scene cannot be rendered
    -- through a target that is mid-surgery. Here the frame is still intact
    -- and the planar pass owns its own colour/depth pair outright.
    local planarTex, planarY = drawPlanar(state, terrain, nbMesh, atlasFor,
                                          Water.reflectCast() and castOnce
                                          or nil,
                                          cx, cy, vw, vh)
    -- the cast goes into the reflection copy only -- see drawWater for why
    -- it cannot be composited yet and why it is drawn through the same
    -- function the real pass below uses
    VoxelScene.drawWater(waterDraws, Water.reflectCast() and castOnce or nil,
                         planarTex, planarY)
  end

  -- AND THE RIPPLE RINGS ON TOP OF IT, BEFORE ANYBODY IS STANDING IN IT.
  --
  -- THIS LINE'S POSITION IS THE WHOLE FIX.  Reported from play: "the ripples
  -- are appearing over the player character make those masked by my character
  -- sprite so they appear behind them".  They were, because they were drawn
  -- by ctx.drawFx -- a 2D overlay over the finished scene -- and a finished
  -- scene already has the player in it.  Here the ring is geometry, and it
  -- goes down AFTER the water it lies on and BEFORE drawCast, so a card
  -- rasterised later simply covers it.  The decal mode writes no depth
  -- (Voxel3D.beginDecal), so the cards meet the exact depth buffer they met
  -- before this pass existed and nothing about their own occlusion changes.
  --
  -- IN-GAME: THE SHALLOW WATER OFF THE BRIDGE ON ROUTE 104, where the two
  -- NPCs stand in the water they are ringing.
  drawRipples(state)

  -- ...AND THE BLOB THE PLAYER IS SITTING IN, on top of the rings, still
  -- before anybody's card. Same position and the same reason: the decal
  -- writes no depth, so the player's own card is rasterised afterwards and
  -- covers the dome, which is the flat game's order too (Player:draw calls
  -- drawSurfBlob and THEN blits the sprite). Outside the `hideMe` test the
  -- cards run under, so it is drawn in FIRST PERSON as well -- the mode the
  -- report names, and the one where it is the only thing under you there is
  -- to see.
  drawSurfBlob(state, me)

  -- Sprite sheets from here to the figure pass: their texture coordinates
  -- mean nothing to the tileset-shaped glass mask, so the glass is off or
  -- the panes' atlas positions stripe the cast with lamplight at night
  Voxel3D.glass(false)

  -- The player's silhouette goes down BEFORE the characters, so the only
  -- thing it can meet in the depth buffer is the WORLD -- terrain, buildings,
  -- trees. Drawn after the solid pass it would meet the player's own card
  -- instead, and every fragment of a figure sits behind the one that just
  -- wrote it, so the silhouette would paint over the player at all times.
  -- Every character then draws on top as usual, which leaves the silhouette
  -- showing in exactly one situation: where the world hides them.
  --
  -- Not in first person: the card it silhouettes is the one the camera is
  -- standing inside, and "the world is in front of the player" is every
  -- wall the player faces.
  if me and not FirstPerson.hidePlayer() then
    Voxel3D.beginGhost()
    drawGhost(me)
    Voxel3D.endGhost()
  end

  -- Characters carry no wireframe out here, whatever the V-GRID row says.
  -- The seams are what makes the WORLD read as built out of voxels, and
  -- the people walking around in it are the one thing that should read as
  -- drawn instead -- a grid over a 16x16 sprite lands a line every couple
  -- of display pixels and turns a face into a mesh. (The battle pass makes
  -- the opposite call for its own combatants, deliberately: that is a
  -- staged shot rather than the world being walked around in -- see
  -- BattleBillboard.)
  --
  -- Characters, normally depth-tested: the camera-ward pull inside
  -- drawEntity resolves the lean-over-the-wall-in-front case, and a
  -- character genuinely behind a building is far deeper and loses the
  -- test, so buildings and trees really occlude.
  drawCast(state, posed, atlasFor)
  -- and the staged fight's mons over them, exactly as they were painted
  -- into the water's reflection copy a few lines up (see drawBattleCards)
  drawBattleCards()
  -- tall grass last, pulled camera-ward exactly as far as the characters
  -- were (same per-vertex shader bias, so grass never drifts either):
  -- relative depth between a walker and the tuft row south of their feet
  -- is preserved, so the row still overdraws feet -- the 3D version of
  -- the GB's grass-over-feet trick -- while grass keeps losing to the
  -- buildings it genuinely stands behind (far deeper than the pull).
  -- the same angle the cards leaned by (leanAngle honours VR's override),
  -- so the tuft rows keep exactly the characters' own depth handicap
  local lean = math.max(leanAngle(), 0.05)
  local pull = VoxelScene.pull(lean)
  Voxel3D.draw(ChunkMesher.grass(state.map), atlasFor(state.map), nil, pull)
  for _, nb in ipairs(state.neighbors or {}) do
    Voxel3D.draw(ChunkMesher.grass(nb.map), atlasFor(nb.map),
                 Mat4.translate(nb.ox, 0, nb.oy), pull)
  end
  -- flower billboards: pulled like the characters and the grass, MINUS
  -- the depth of 8 world pixels along the view (8 sin a -- the camera
  -- looks along (0, -cos a, -sin a), so that is exactly one tile row of
  -- northness). A pure depth handicap with zero screen drift: every
  -- flower is judged as if it stood one tile row further north. The
  -- character card's feet plane sits at its cell's MIDDLE (py + 8), so
  -- a flower on the walker's own cell (z +4 or +12 across the cell)
  -- lands behind the card and the player obscures the patch they stand
  -- ON, while the nearest flower of the cell south (+20) stays in front
  -- and keeps overdrawing their feet.
  local fpull = math.max(0, pull - 8 * math.sin(lean))
  -- flowers are snugged casters too, so they read their own shadowing
  -- through the same snugged transform the sun stored them with
  Voxel3D.draw(ChunkMesher.flowers(state.map), atlasFor(state.map), nil,
               fpull, ShadowMap.snug(nil))
  for _, nb in ipairs(state.neighbors or {}) do
    Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                 Mat4.translate(nb.ox, 0, nb.oy), fpull,
                 ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
  end

  -- The VR pokedex in the player's left hand, last of all: a prop over
  -- the world drawn with real depth, so leaning it into a wall still
  -- occludes honestly. Its frame only exists while a session is live and
  -- the left hand is tracked (VR.lua sets it), so every flat frame skips
  -- this in one field read. No wireframe and no glass, like the cast:
  -- the device is a drawing riding the scene, not part of the terrain.
  if Pokedex.frame then
    Voxel3D.glass(false)
    Voxel3D.seams(false)
    Pokedex.draw()
    Voxel3D.seams(true)
    Voxel3D.glass(true)
  end

  -- HORDE MODE's handgun, in the same slot and for the same reasons: a
  -- prop over the world with real depth, no wireframe and no glass. In VR
  -- it rides the tracked right hand (lib/VR placed it this frame); on the
  -- flat screen it is carried by the camera, which is why it draws here
  -- rather than in the overlay -- a view model that is 2D cannot be
  -- occluded by the wall the player just backed into.
  do
    local HordeGun = V.require("HordeGun")
    if HordeGun.visible() then
      Voxel3D.glass(false)
      Voxel3D.seams(false)
      HordeGun.draw()
      Voxel3D.seams(true)
      Voxel3D.glass(true)
    end
  end

  end   -- drawScene

  if not eyes then
    if not Voxel3D.beginScene(w, h, cx, cy, vw, vh, skyFor(state.map)) then
      return nil
    end
    drawScene()
    local out1 = Voxel3D.endScene()
    Perf.add("VoxelScene.render", tR)
    return out1
  end

  -- The VR frame: the same scene once per eye, each into its own named
  -- canvas slot under its own placed camera. `adopt` hands the eye's
  -- record to FirstPerson as the live rig, which is what turns the
  -- billboards toward THIS eye in first person (cardBlend keys on rig
  -- identity -- see FirstPerson) and leaves them leaning in the diorama,
  -- where the blend is zero.
  local out = {}
  for i, eye in ipairs(eyes) do
    Voxel3D.camera = eye.camera
    if eye.adopt then FirstPerson.adoptVReye(eye.camera) end
    if not Voxel3D.beginScene(eye.w, eye.h, cx, cy, vw, vh,
                              skyFor(state.map), eye.slot) then
      return nil
    end
    drawScene()
    out[i] = Voxel3D.endScene()
  end
  Perf.add("VoxelScene.render", tR)
  return out
end

return VoxelScene
