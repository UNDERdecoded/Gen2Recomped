-- Voxel world mode: THE GEN 3 ARM.
--
-- Everything this mod knows about building Hoenn as geometry lives here, and
-- nothing outside this file needs to know Gen 3 exists beyond asking
-- `Gen3.forMap(map)` and getting nil back on Kanto and Johto.
--
-- ---------------------------------------------------------------------------
-- WHY GEN 3 IS NOT "GEN 2 WITH DIFFERENT ART"
-- ---------------------------------------------------------------------------
--
-- The mod's Gen 1 and Gen 2 paths spend most of their effort inferring, from
-- pixels, three things the drawing does not state: what a cell IS, whether the
-- player passes in front of it or behind it, and how high the ground under it
-- sits.  Gen 3 states all three outright, and the whole point of this file is
-- to stop guessing where the cartridge already answered.
--
--   BEHAVIOUR BYTE   one per metatile, out of the attributes word.  240
--                    named values: tall grass, deep water, a ledge you jump
--                    SOUTH over, an animated door, a counter, a bookshelf,
--                    ice, a floating log, a bridge over the ocean.  Gen 2's
--                    equivalent is a collision class with about a dozen
--                    meanings and no vocabulary for furniture at all.
--
--   LAYER TYPE       one per metatile, also out of the attributes word.  A
--                    Gen 3 metatile is drawn in two halves and the layer type
--                    says which background each half goes to -- which is to
--                    say whether the top half is drawn ABOVE the player
--                    (cover: a treetop, a roof, the upper storey of a house)
--                    or BELOW them (a second course of ground: a carpet over
--                    a floor, a path over grass).  That is exactly the
--                    question `Structures`' background flood exists to guess
--                    at on Gen 1 and Gen 2, and here it is a field.
--
--   ELEVATION        one per CELL, in the map's own blockdata.  Gen 2 records
--                    no height whatsoever -- a terrace and the grass below it
--                    are both collision $00, which is why the Johto profile
--                    has to recognise terraces by their FLOOR ART.  Gen 3
--                    hands over the Y axis directly, and it is what puts
--                    Route 110's cycling road over the sea rather than in it,
--                    and what gives Sootopolis its crater.
--
-- ---------------------------------------------------------------------------
-- THE ONE STRUCTURAL COINCIDENCE THAT MAKES THIS CHEAP
-- ---------------------------------------------------------------------------
--
-- A Gen 3 METATILE is 16x16 pixels and IS one collision cell.  A Gen 1/Gen 2
-- CELL is also 16x16 -- 2x2 of the 8px tiles the mesher works in.  So the
-- mesher's tile grid, its cell arithmetic (`math.floor(tx / 2)`), its 8px
-- side-band courses, its ambient occlusion and its whole run machinery are
-- ALREADY the right shape for Gen 3.  Only two things differ:
--
--   * a Gen 3 BLOCK is 2 tiles on a side, not 4 (`def.width * 4` is wrong);
--   * there is no tile id -- there is a metatile id, and the sheet is 16x16
--     CELLS rather than 8x8 tiles.
--
-- The second is answered by a SYNTHETIC TILE ID, and this is the load-bearing
-- trick of the file:
--
--     tileId = metatileId * 4 + quadrant,  quadrant = (ty % 2) * 2 + (tx % 2)
--
-- One metatile becomes four 8px tiles in the mesher's own numbering, in
-- reading order.  Every consumer that treats a tile id as an opaque number
-- keeps working untouched; only the UV lookup has to know, and it is one
-- function.  Nothing else in the mod acquires a Gen 3 branch.
--
-- ---------------------------------------------------------------------------
-- WHAT IS DELIBERATELY *NOT* DONE HERE
-- ---------------------------------------------------------------------------
--
-- There is no second mesh for the "above player" layer, and that is a design
-- decision rather than an omission.  Drawing a treetop over the player is a
-- two-dimensional trick for depicting height on a flat map.  In a diorama the
-- treetop is simply UP, and the depth buffer does the rest.  So the two baked
-- sheets are composited into ONE atlas for texturing, and the top layer is
-- read instead as a HEIGHT SIGNAL: a metatile whose top half is drawn above
-- the player is a metatile with something standing on it.
--
-- the mod namespace (see main.lua): V.require / V.data
local V = ...

local Gen3 = {}

-- 16x16 metatiles per sheet row -- Gen3Tiles.SHEET_COLS.  Read from the
-- engine when it will answer and pinned here so a headless test needs no host.
local SHEET_COLS = 16
local CELL = 16          -- a metatile edge, in world pixels
local TILE = 8           -- the mesher's own quad edge
local COURSE = 16        -- one elevation step, in world pixels

Gen3.SHEET_COLS = SHEET_COLS
Gen3.CELL = CELL
Gen3.COURSE = COURSE

-- HOW THIS FILE REACHES THE ENGINE, and the mistake worth not repeating.
--
-- `_G.Game` IS NIL IN A REAL SESSION.  The engine's Game is a module, reached
-- with `require("src.core.Game")` -- which is what every other file in this
-- mod does -- and it is not published as a global.  Reading `_G.Game` cost
-- both halves of the Gen 3 arm at once and neither said so clearly:
--
--   * `gen3WorldFor` was never found, so the engine seam looked absent even
--     on a host that publishes it, and the mod fell back to baking the pair
--     itself;
--   * and the fallback then could not find `Game.data.map_tilesets` either,
--     so it reported "no map_tilesets entry for primary TILESET_03DF704" --
--     which reads like missing DATA and is really a missing lookup.
--
-- `_G.Game` is kept as a second choice purely so the headless tests, which
-- have no `src.core.Game` to require, still work.
local function engineGame()
  local ok, Game = pcall(require, "src.core.Game")
  if ok and type(Game) == "table" and (Game.data or Game.overworld) then
    return Game
  end
  -- The module exists from the first require but its `data` and `overworld`
  -- are only populated once a game is loaded, so a bare module is not an
  -- answer -- and a harness that supplies its own is.
  local g = rawget(_G, "Game")
  if type(g) == "table" then return g end
  return (ok and type(Game) == "table") and Game or nil
end

local function engineData()
  local Game = engineGame()
  return Game and Game.data or nil
end

Gen3.engineData = engineData

-- ---------------------------------------------------------------------------
-- IS THIS GEN 3?
--
-- Asked of the TILESET, never of GameVersion, for the same reason the engine
-- asks it that way (src/world/Map.lua, "HOW BIG IS A BLOCK"): the map editor
-- and the save converter both build Map objects with no game selected, and a
-- Gen 3 tileset record is recognisable on its own -- it is the one that says
-- a block is 2 tiles wide and holds a single cell.  A Gen 1 or Gen 2 tileset
-- sets neither field, and the engine's own default for both is Gen 1's.
-- ---------------------------------------------------------------------------
function Gen3.isGen3(tileset)
  if type(tileset) ~= "table" then return false end
  return tonumber(tileset.blockTiles) == 2 and tonumber(tileset.blockCells) == 1
end

function Gen3.mapIsGen3(map)
  return map ~= nil and Gen3.isGen3(map.tileset)
end

-- ---------------------------------------------------------------------------
-- THE SYNTHETIC TILE ID
-- ---------------------------------------------------------------------------

function Gen3.tileId(metatile, tx, ty)
  return (tonumber(metatile) or 0) * 4 + (ty % 2) * 2 + (tx % 2)
end

-- TILE ID AT 8px TILE COORDINATES, WHICHEVER GENERATION THE MAP IS.
--
-- `Map:tileAt` reads `tileset.blocks` -- the Gen 1/2 block table, four
-- rows of four tile ids per 16x16 cell.  A Gen 3 tileset entry has no such
-- field: its metatiles live in map_tilesets.lua and the BLOCK ID IS THE
-- METATILE, which is what Gen3.tileId turns into the synthetic 2x2 id the
-- relaid sheet is addressed by.
--
-- So `map:tileAt` on a Hoenn map indexes a nil table and THROWS.  Inside a
-- mesh build that throw is caught by the job runner, the slot caches a
-- failure and is never retried, and the map stays FLAT for the rest of the
-- session with one line in the log -- which is exactly what "this town
-- still looks the same" is from the outside.  Every reader in this mod
-- goes through here instead, so a Gen 1 map keeps the block table it has
-- always used and a Gen 3 map answers from its own metatiles.
function Gen3.tileAt(map, tx, ty)
  if not map then return nil end
  local ts = map.tileset
  if ts and ts.blocks then return map:tileAt(tx, ty) end
  local okB, id = pcall(map.blockAt, map, math.floor(tx / 2), math.floor(ty / 2))
  if not okB or id == nil then return nil end
  return Gen3.tileId(id, tx, ty)
end

function Gen3.metatileOf(tileId)
  return math.floor((tonumber(tileId) or 0) / 4)
end

function Gen3.quadrantOf(tileId)
  return (tonumber(tileId) or 0) % 4
end

-- Pixel origin of a synthetic tile id on the composited sheet.  This is the
-- single place the 16x16-cell layout is stated; ChunkMesher's `uvRect` and
-- Structures' pixel readers both go through it.
function Gen3.tileOrigin(tileId, cols)
  cols = cols or SHEET_COLS
  local id = tonumber(tileId) or 0
  local m, q = math.floor(id / 4), id % 4
  local ax = (m % cols) * CELL + (q % 2) * TILE
  local ay = math.floor(m / cols) * CELL + math.floor(q / 2) * TILE
  return ax, ay
end

-- The size of the synthetic tile-id space for a pair, which is what
-- TileShape.forMap needs in place of (imageWidth/8) * (imageHeight/8).
function Gen3.tileCount(metatiles)
  return (tonumber(metatiles) or 0) * 4
end

-- HOW LONG THE METATILE ID SPACE IS, answerable WITHOUT a built context --
-- because a shape table sized from a context that failed to build is a map
-- with most of its cells missing, and that must not be a way to fail.
--
-- The pair record's own `metatileCount` is the sum of the two halves, which
-- is NOT the id space: metatileBank splits at `metatilesInPrimary` (512), so
-- id 512 is the secondary's first slot whatever the primary actually filled
-- in.  That is right for the outdoor primary, which defines all 512, and
-- wrong for the indoor one, which defines EIGHT -- every room in the game
-- addresses ids 513 and up.  So prefer the context (which asks Gen3Tiles,
-- and Gen3Tiles knows), and when there is none take the generous bound: an
-- id space that is too long costs empty table slots and nothing else.
function Gen3.idSpace(tileset, ctx)
  if ctx and (ctx.metatiles or 0) > 0 then return ctx.metatiles end
  local data = engineData()
  local layout = data and data.constants and data.constants.gen3Layout
  local inPrimary = tonumber(layout and layout.metatilesInPrimary) or 512
  local total = tonumber(tileset and tileset.metatileCount) or 0
  return math.max(inPrimary + total, inPrimary * 2)
end

-- ---------------------------------------------------------------------------
-- THE ENGINE SEAM
--
-- `OverworldState:gen3WorldFor` publishes the baked sheets, the metatile
-- attributes and the per-cell elevation.  It is new, so this falls back to
-- baking through `src.render.Gen3Tiles` directly when the host predates it --
-- and says which path it took, once, because "the 3D world is empty" and "the
-- 3D world is empty AND the host is old" are different bug reports.
-- ---------------------------------------------------------------------------

local reported = {}

local function say(key, fmt, ...)
  if reported[key] then return end
  reported[key] = true
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and Logger and Logger.info then
    pcall(Logger.info, "gen3 voxel: " .. fmt, ...)
  end
end

local function warn(key, fmt, ...)
  if reported[key] then return end
  reported[key] = true
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and Logger and Logger.warn then
    pcall(Logger.warn, "gen3 voxel: " .. fmt, ...)
  end
end

Gen3.warn = warn

local function engineWorld(map)
  local Game = engineGame()
  local ow = Game and (Game.overworld or Game.world) or nil
  if not (ow and type(ow.gen3WorldFor) == "function") then return nil end
  local got, world = pcall(ow.gen3WorldFor, ow, map.def, map, map.tileset)
  if got and type(world) == "table" and world.bottom then
    say("seam", "using the engine's gen3WorldFor seam")
    return world
  end
  return nil
end

-- The fallback: bake the pair ourselves.  Same code the engine's own 2D path
-- uses, so the two cannot disagree about what a metatile looks like.
local function modWorld(map)
  local tileset = map.tileset
  local data = engineData()
  local store = data and data.map_tilesets
  local primary = store and store[tileset.primaryKey]
  if not primary then
    warn("nostore", "no map_tilesets entry for primary %s -- the world cannot "
         .. "be textured and nothing will be meshed",
         tostring(tileset.primaryKey))
    return nil
  end
  local okMod, Gen3Tiles = pcall(require, "src.render.Gen3Tiles")
  if not (okMod and Gen3Tiles) then
    warn("nogen3tiles", "src.render.Gen3Tiles is unavailable on this host")
    return nil
  end
  local layout = data and data.constants and data.constants.gen3Layout
  local okNew, tiles = pcall(Gen3Tiles.new, {
    primary = primary,
    secondary = tileset.secondaryKey and store[tileset.secondaryKey] or nil,
  }, layout)
  if not (okNew and tiles) then
    warn("nonew", "Gen3Tiles.new failed: %s", tostring(tiles))
    return nil
  end
  say("fallback", "the host does not publish gen3WorldFor -- baking the pair "
      .. "in the mod instead")
  local cols, _, w, h = tiles:sheetLayout()
  return {
    generation = 3, tileset = tileset, pair = tileset,
    bottom = false, top = false,           -- images are the atlas's business
    width = w, height = h, cols = cols or SHEET_COLS, cell = CELL,
    metatiles = tiles:metatileCount(),
    tiles = tiles,
    attributes = function(id)
      local ok2, b, l = pcall(tiles.attributes, tiles, tonumber(id) or 0)
      if not ok2 then return 0, 0 end
      return b or 0, l or 0
    end,
    topIsAbovePlayer = function(id)
      if type(tiles.topIsAbovePlayer) ~= "function" then return true end
      local ok2, v = pcall(tiles.topIsAbovePlayer, tiles, tonumber(id) or 0)
      return (not ok2) or (v and true or false)
    end,
  }
end

-- ---------------------------------------------------------------------------
-- ELEVATION -> WORLD HEIGHT
--
-- The raw value is NOT a height.  Emerald's levels are labels, not rungs: a
-- map uses whichever of 0..15 it needs and skips the rest, so Sootopolis runs
-- 0,1,3,4,5,7,9 and Fortree runs 0,3,4,15.  Reading the number as a course
-- count would put a 96px cliff where Sootopolis draws two, and a 192px one
-- where Fortree draws a rope bridge.
--
-- So RANK them.  Collect the levels a map actually uses, sort them, and let
-- consecutive ranks be one course apart.  Two neighbouring terraces are then
-- always exactly one course apart, which is what the art draws, whatever
-- numbers the cartridge happened to label them with.
--
-- The four reserved values keep their meanings:
--
--   0  TRANSITION   "compatible with any level".  The tempting reading is
--                   "a ramp", and the tempting rule is "take the highest
--                   neighbour, because a transition is the surface you are
--                   stepping onto".  Both are wrong, and the map data says
--                   so plainly: elevation 0 tracks the BLOCKED cells almost
--                   exactly -- Fortree 560 zeroes against 546 blocked cells,
--                   Sootopolis 2079 against 2091, Rustboro 1033 against 1096,
--                   Route 119 2794 against 2963.  It is overwhelmingly the
--                   marker on scenery nobody can stand on, not on ramps.
--
--                   So a blocked transition cell takes the DATUM and nothing
--                   more -- its real height is measured from its art by
--                   `Structures.buildVolume`, which also reads the ground it
--                   is founded on off the flat cell in front of it.  Only a
--                   PASSABLE transition cell is a genuine ramp, and it takes
--                   the LOWEST real level around it: a ramp read high puts a
--                   shelf at the bottom of the slope, which is a step you can
--                   see, while a ramp read low is a step at the top that the
--                   terrace above it already hides.
--   1  SURF         the water surface.  Below the datum, where `water`
--                   already sits.
--   3  DEFAULT      ordinary ground.  The datum, always, so a map with no
--                   terraces at all is dead flat rather than floating.
--   15 MULTI_LEVEL  a bridge deck: "do not change the walker's elevation
--                   here".  One course above whatever it spans.
-- ---------------------------------------------------------------------------

local ELEV_TRANSITION, ELEV_SURF, ELEV_DEFAULT, ELEV_MULTI = 0, 1, 3, 15

-- MB_MOUNTAIN_TOP IS THE CARTRIDGE NAMING A ROCK MASS.
--
-- Emerald has exactly one behaviour byte that says "this cell is the top of a
-- mountain", and it uses it for nothing else.  Two art readings were
-- overruling it on Route 114 and Route 115 and nowhere else in Hoenn -- see
-- `railStands` and the `motif` branch of `ctx.roleAt`.
local MB_MOUNTAIN_TOP = 0x0C
local NEIGHBOURS = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

local function buildElevationRanks(cells)
  local seen, list = {}, {}
  for i = 1, #cells do
    local e = cells[i]
    if e and e ~= ELEV_TRANSITION and e ~= ELEV_MULTI and e ~= ELEV_SURF
       and not seen[e] then
      seen[e] = true
      list[#list + 1] = e
    end
  end
  table.sort(list)
  local rank, datum = {}, nil
  for i, e in ipairs(list) do
    rank[e] = i
    if e == ELEV_DEFAULT then datum = i end
  end
  -- No cell on this map is at the default level (an all-terrace interior, or
  -- Pacifidlog, which is water and rafts).  Pin the datum to the LOWEST level
  -- present rather than to nothing, so the map still lands on the world floor.
  if not datum then datum = 1 end
  local height = {}
  for e, i in pairs(rank) do height[e] = (i - datum) * COURSE end
  height[ELEV_SURF] = -COURSE / 8          -- the water class's own recess
  return height, #list
end

-- ---------------------------------------------------------------------------
-- BEHAVIOUR BYTE -> VOXEL CLASS
--
-- The table itself lives in data/gen3_shapes.lua so it can be read and edited
-- as data, the way the Gen 1 and Gen 2 profiles are.  This is only the lookup,
-- and the rules that surround it.
-- ---------------------------------------------------------------------------

local function spec()
  local ok, s = pcall(V.data, "gen3_shapes")
  if ok and type(s) == "table" then return s end
  return nil
end

Gen3.spec = spec

-- ---------------------------------------------------------------------------
-- THE PER-MAP CONTEXT
--
-- Weakly keyed on the map, like TileShape's own sealed-pocket cache, because
-- everything in it is a property of ONE map's blockdata and the engine reuses
-- map objects across transitions.
-- ---------------------------------------------------------------------------

local ctxCache = setmetatable({}, { __mode = "k" })

-- How many times a map may fail to produce a world record before the miss is
-- treated as permanent.  "The world record does not exist yet" and "this pair
-- can never build one" look identical from here and need opposite handling:
-- the first is the ordinary first frames of a map, where the mesh is queued
-- before the engine has published anything, and the second is a broken pair
-- that must not be retried once a frame forever.
local CTX_RETRIES = 8
local ctxMisses = setmetatable({}, { __mode = "k" })

-- A FLOOR IS NOT A FLIGHT, EVEN WHEN IT IS DRAWN IN PLANKS.
--
-- MOTIVATED BY THE STARTER HOUSES IN LITTLEROOT TOWN, WHOSE FLOORBOARDS
-- WERE MESHED AS A STAIRCASE FILLING THE ROOM.
--
-- `ctx.roleAt`'s stair arm reads "banded art that fills its cell and draws
-- no face", and it separates a flight from Slateport's decking and Route
-- 114's rock on `solid` and `face`.  It cannot separate a flight from an
-- INDOOR PLANK FLOOR, because a plank floor is honestly all three things:
--
--   Sootopolis 580/581   banded  cap 16  face 0  solid 1.00   a flight
--   Littleroot 513/517   banded  cap 16  face 0  solid 1.00   floorboards
--
-- Every number the test has is identical.  Brendan's house reported SEVEN
-- flights in one room, all of them flat, and the room was meshed as steps.
--
-- What separates them is not the tile, it is the SHAPE OF THE RUN, and two
-- readings settle it, both structural rather than chosen:
--
--   THE PLAYER IS ONE CELL WIDE.  A flight is something you walk up, so
--   Emerald draws one one or two cells across.  Over all 518 maps, 527 of
--   the 538 connected runs of tread art are at most two cells across:
--
--     cells across   1 -> 494    2 -> 33    3 -> 2    4 -> 5    5..7 -> 4
--
--   A WIDE FLIGHT IS A CHANNEL CUT THROUGH SOMETHING.  Mt Pyre's grand
--   stairs are three cells across -- the two runs in the game that are --
--   and every cell flanking them, down both sides, is blocked: they are cut
--   into the mountain.  A room is not.  The eleven runs three or more cells
--   across separate with nothing in between:
--
--     MtPyre_Exterior      3x3, 3x4     flanks blocked 1.00   FLIGHTS
--     FortreeCity_House1-5 8x4          flanks blocked 0.81   floors
--     Littleroot houses    6x7 .. 10x7  flanks blocked 0.40-0.55
--
-- So: a run of tread art at most two cells across is a flight; a wider one
-- is a flight only if it is cut on EVERY flanking cell.  213 cells on nine
-- maps stop being stairs -- the four Littleroot starter-house floors and
-- the five Fortree tree-hut floors -- and nothing else in Hoenn moves.
--
-- Answered per map and memoised, because the shape of a run is not a
-- property of a cell.  The scan re-implements the stair ART test rather
-- than calling `ctx.roleAt`, which would re-enter this function per cell.
local floorPlateCache = setmetatable({}, { __mode = "k" })

local function floorPlateFor(map, ctx)
  if not (ctx and ctx.metatileAt and ctx.metaRole and ctx.blockedAt) then
    return nil
  end
  local hit = floorPlateCache[ctx]
  if hit then return hit end
  local plate = {}
  floorPlateCache[ctx] = plate        -- publish first: the scan must not
                                      -- re-enter this function per cell
  local def = map and map.def
  local W = math.floor(tonumber(def and def.width) or 0)
  local H = math.floor(tonumber(def and def.height) or 0)
  if W < 1 or H < 1 then return plate end
  local an = Gen3.analyse(map.tileset)
  local stats = an and an.stats

  local function key(cx, cy) return cy * 8192 + cx end
  local function inb(cx, cy)
    return cx >= 0 and cy >= 0 and cx < W and cy < H
  end
  -- the same three readings the stair arm makes, and no others
  local tread = {}
  local function isTread(cx, cy)
    local k = key(cx, cy)
    local t = tread[k]
    if t ~= nil then return t end
    t = false
    local okB, blocked = pcall(ctx.blockedAt, cx, cy)
    if okB and not blocked then
      local okM, m = pcall(ctx.metatileAt, cx, cy)
      if okM and m then
        local okR, art, _, _, face = pcall(ctx.metaRole, m)
        if okR and art == "banded" and (tonumber(face) or 0) <= 1 then
          local st = stats and stats[m]
          if not (st and (st.solid or 0) < 0.75) then t = true end
        end
      end
    end
    tread[k] = t
    return t
  end

  local seen = {}
  for cy = 0, H - 1 do
    for cx = 0, W - 1 do
      local k0 = key(cx, cy)
      if isTread(cx, cy) and not seen[k0] then
        local queue, qi, cells = { { cx, cy } }, 1, {}
        seen[k0] = true
        local x0, x1, y0, y1 = cx, cx, cy, cy
        while qi <= #queue do
          local c = queue[qi]
          qi = qi + 1
          cells[#cells + 1] = c
          if c[1] < x0 then x0 = c[1] end
          if c[1] > x1 then x1 = c[1] end
          if c[2] < y0 then y0 = c[2] end
          if c[2] > y1 then y1 = c[2] end
          for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
            local nx, ny = c[1] + d[1], c[2] + d[2]
            local nk = key(nx, ny)
            if inb(nx, ny) and not seen[nk] and isTread(nx, ny) then
              seen[nk] = true
              queue[#queue + 1] = { nx, ny }
            end
          end
        end
        local w, h = x1 - x0 + 1, y1 - y0 + 1
        local across = (w < h) and w or h
        if across >= 3 then
          -- a flight climbs along its LONGER axis, so the flanks are the
          -- neighbours across the shorter one
          local ds = (h >= w) and { { -1, 0 }, { 1, 0 } }
                              or  { { 0, -1 }, { 0, 1 } }
          local cut = true
          for _, c in ipairs(cells) do
            for _, d in ipairs(ds) do
              local nx, ny = c[1] + d[1], c[2] + d[2]
              if not (inb(nx, ny) and isTread(nx, ny)) then
                if inb(nx, ny) then
                  local okB, blocked = pcall(ctx.blockedAt, nx, ny)
                  if not (okB and blocked) then cut = false end
                end
              end
            end
            if not cut then break end
          end
          if not cut then
            for _, c in ipairs(cells) do plate[key(c[1], c[2])] = true end
          end
        end
      end
    end
  end
  return plate
end

function Gen3.forMap(map)
  if not Gen3.mapIsGen3(map) then return nil end
  local hit = ctxCache[map]
  if hit ~= nil then return hit or nil end

  local world, seam = engineWorld(map), "engine"
  if not world then world, seam = modWorld(map), "mod" end
  if not world then
    -- NOT NECESSARILY A FAILURE, AND THIS USED TO BE CACHED AS ONE.
    --
    -- `ctxCache[map] = false` sat above this line, so the very first ask --
    -- which routinely lands before the engine has published the map's world
    -- record, and whose own log line says "no context built yet" -- poisoned
    -- that map for the rest of its life. Every later caller got nil, and the
    -- consumers that reached for the context to size the atlas fell back to
    -- Gen 1's 128x48. Let it retry a bounded number of times instead.
    local n = (ctxMisses[map] or 0) + 1
    ctxMisses[map] = n
    if n >= CTX_RETRIES then
      ctxCache[map] = false
      warn("noctx", "%s never published a world record after %d tries -- its "
           .. "world will mesh flat", tostring(map.id or "?"), n)
    end
    return nil
  end
  ctxMisses[map] = nil
  -- Re-entrancy guard only: a context whose build asks for itself (a profile
  -- lookup that reaches back through the map) must not recurse. Replaced by
  -- the real context at the end of the build.
  ctxCache[map] = false

  local def = map.def or {}
  local width = tonumber(def.width) or 0
  local height = tonumber(def.height) or 0
  local elevationCells = def.elevationCells
  local collisionCells = def.collisionCells

  local elevHeight, levels = nil, 0
  if elevationCells then
    elevHeight, levels = buildElevationRanks(elevationCells)
  end

  local ctx = {
    world = world,
    -- WHICH PATH BUILT THIS WORLD, stated rather than inferred.  Both records
    -- carry `generation = 3`, so the first version of the diagnostic reported
    -- `seam=engine` on every run including the headless harness's fallback --
    -- which is precisely the fact the diagnostic existed to establish.
    seam = seam,
    map = map,
    tileset = map.tileset,
    cols = world.cols or SHEET_COLS,
    cell = CELL,
    metatiles = world.metatiles or 0,
    width = width,
    height = height,
    elevationCells = elevationCells,
    collisionCells = collisionCells,
    elevHeight = elevHeight,
    levels = levels,
    spec = spec(),
    -- memo tables, all keyed by metatile id
    attrCache = {},
    classCache = {},
  }

  -- --- raw reads ----------------------------------------------------------

  local function indexOf(cx, cy)
    if width <= 0 or height <= 0 then return nil end
    if cx < 0 or cy < 0 or cx >= width or cy >= height then return nil end
    return cy * width + cx + 1
  end
  ctx.indexOf = indexOf

  -- THE BORDER PATCH TILES; IT DOES NOT SMEAR.
  --
  -- A Gen 3 map is surrounded by a 2x2 patch of metatiles repeated outward --
  -- in Hoenn almost always the four quarters of a tree (468/469 over 476/477
  -- on the General pair). `map:blockAt` border-extends by clamping, so every
  -- cell outside the body answered the patch's FIRST entry: three of every
  -- four ring cells were classified from the wrong quarter of the drawing.
  -- It happened to look passable because all four quarters are foliage and
  -- all four read leafy, but the 2x2 crown scan was aligning against a
  -- uniform field rather than the motif, and any border whose quarters differ
  -- -- water meeting a cliff, a patterned floor -- would have read as a wall
  -- of whichever corner came first.
  local borderPatch = nil
  do
    local b = def.border
    if type(b) == "string" and #b >= 8 then
      borderPatch = {}
      for i = 0, 3 do
        local lo, hi = b:byte(i * 2 + 1), b:byte(i * 2 + 2)
        borderPatch[i + 1] = (lo + hi * 256) % 1024
      end
    elseif def.borderBlock then
      local m = def.borderBlock
      borderPatch = { m, m, m, m }
    end
  end

  function ctx.metatileAt(cx, cy)
    if cx < 0 or cy < 0 or cx >= width or cy >= height then
      if borderPatch then
        return borderPatch[(cy % 2) * 2 + (cx % 2) + 1]
      end
    end
    if type(map.blockAt) ~= "function" then return nil end
    local ok, id = pcall(map.blockAt, map, cx, cy)
    if not ok then return nil end
    return id
  end

  function ctx.attributes(metatile)
    local m = tonumber(metatile) or 0
    local c = ctx.attrCache[m]
    if c then return c[1], c[2] end
    local b, l = 0, 0
    if type(world.attributes) == "function" then
      b, l = world.attributes(m)
    end
    ctx.attrCache[m] = { b or 0, l or 0 }
    return b or 0, l or 0
  end

  function ctx.coverAt(metatile)
    if type(world.topIsAbovePlayer) == "function" then
      return world.topIsAbovePlayer(metatile) and true or false
    end
    local _, layer = ctx.attributes(metatile)
    return layer ~= 1
  end

  -- 0 means passable.  On Gen 3 passability is the CELL's business, not the
  -- tileset's: a house front and its doorway are the same metatile.
  function ctx.offMap(cx, cy)
    return cx < 0 or cy < 0 or cx >= width or cy >= height
  end

  function ctx.blockedAt(cx, cy)
    if not collisionCells then return false end
    local i = indexOf(cx, cy)
    if not i then return true end          -- off the map reads as solid
    return (collisionCells[i] or 0) ~= 0
  end

  function ctx.elevationAt(cx, cy)
    if not elevationCells then return nil end
    local i = indexOf(cx, cy)
    return i and elevationCells[i] or nil
  end

  -- --- the height field ---------------------------------------------------

  local groundCache = {}

  -- The world Y of the GROUND at a cell, before anything standing on it.
  -- STAIRS AND RAMPS CLIMB.
  --
  -- Emerald marks the cells of a staircase, a ramp or a cliff lip with
  -- elevation 0 -- "matches anything", so the walker keeps whichever level
  -- they arrived on and the game never has to decide.  Reading that as the
  -- LOWEST level around it is right for a lip and wrong for the thing it is
  -- most often drawn as: a flight of steps.  Lavaridge's stairs, Rustboro's
  -- street flights and every terrace ramp in Hoenn lay flat on the bottom
  -- level with the whole rise hidden in an invisible wall at the top -- steps
  -- drawn on the ground, leading nowhere.
  --
  -- So a chain of them climbs.  The connected run of ramp cells is found, the
  -- real levels it touches give the bottom and the top, and each cell is
  -- placed by how far it is between the two -- which is a staircase.  The
  -- ends stay strictly inside the gap ((i+1)/(n+1)) so the bottom step still
  -- rises off the low ground and the top one still steps up to the high, and
  -- a one-cell ramp lands halfway rather than at either end.
  local rampCache = nil
  -- the cells of the chains above that are a FACE rather than a flight; see
  -- "A LADDER IS A FACE, NOT A FLIGHT" below.  `gradeGen3Terrain` reads this
  -- through `Gen3.faceRampAt` so it does not grade a drawn face back down to
  -- one course above the street it stands on.
  local faceRamp = nil
  local function passableRamp(x, y)
    if x < 0 or y < 0 or x >= width or y >= height then return false end
    return ctx.elevationAt(x, y) == ELEV_TRANSITION and not ctx.blockedAt(x, y)
  end
  -- IS THIS CELL DRAWN AS TREADS?
  --
  -- The art test `ctx.roleAt` uses to call a walkable cell a `stair` --
  -- banded art that fills its cell and draws no face -- written here as a
  -- pure function of the metatile so the height field can ask it without
  -- re-entering `roleAt` (roleAt -> isBuildingCell -> buildings -> roofAt ->
  -- sceneryAt reaches back into this file and would cache a half-built
  -- answer for good, the same trap `leafyMeta` is written around).
  local function treadMeta(m)
    if m == nil then return false end
    local art, _, _, face = ctx.metaRole(m)
    if art ~= "banded" then return false end
    if (tonumber(face) or 0) > 1 then return false end
    local an = Gen3.analyse(map.tileset)
    local st = an and an.stats and an.stats[m]
    return st ~= nil and (st.solid or 0) >= 0.75
  end
  local function rampHeightAt(cx, cy)
    if rampCache == nil then
      rampCache = {}
      faceRamp = {}
      if elevHeight then
        local seen = {}
        for sy = 0, height - 1 do
          for sx = 0, width - 1 do
            if not seen[sy * 4096 + sx] and passableRamp(sx, sy) then
              local chain, stack = {}, { { sx, sy } }
              seen[sy * 4096 + sx] = true
              while #stack > 0 do
                local c = table.remove(stack)
                chain[#chain + 1] = c
                for _, d in ipairs(NEIGHBOURS) do
                  local nx, ny = c[1] + d[1], c[2] + d[2]
                  local nk = ny * 4096 + nx
                  if not seen[nk] and passableRamp(nx, ny) then
                    seen[nk] = true
                    stack[#stack + 1] = { nx, ny }
                  end
                end
              end
              -- the real levels this chain runs between
              local lo, hi = nil, nil
              for _, c in ipairs(chain) do
                for _, d in ipairs(NEIGHBOURS) do
                  local ne = ctx.elevationAt(c[1] + d[1], c[2] + d[2])
                  if ne and ne ~= ELEV_TRANSITION and ne ~= ELEV_MULTI
                     and ne ~= ELEV_SURF then
                    local nh = elevHeight[ne]
                    if nh then
                      if lo == nil or nh < lo then lo = nh end
                      if hi == nil or nh > hi then hi = nh end
                    end
                  end
                end
              end
              -- A LADDER IS A FACE, NOT A FLIGHT.
              --
              -- MOTIVATED BY FORTREE CITY'S FIVE LADDERS -- (10,5..6),
              -- (25,5..6), (32,5..6), (12,15..16) and (37,15..16) -- the
              -- climbs from the street up to the tree platforms.
              --
              -- Everything below spreads a transition chain one course per
              -- cell, which is a staircase, and Emerald draws a staircase as
              -- TREADS: banded art that fills its cell and paints no face,
              -- which is exactly the reading `roleAt` already calls `stair`.
              -- A ladder is drawn the other way round -- two cells of rungs
              -- lying flat against the trunk under the deck, `roleAt` = floor
              -- on both -- and there is nothing to stand on halfway up it.
              -- Spread anyway, Fortree's ladders descended 32 -> 16 -> 0 and
              -- read as two steps cut into the tree.
              --
              -- So where NO cell of the chain is drawn as a tread, AND the
              -- chain's drawing has a vertical face in it, the chain is not a
              -- flight: it is the face of the level it climbs to, and every
              -- cell of it stands at that level.
              --
              -- ...AND A LIP IS NOT A LADDER EITHER.  The second half of that
              -- is what separates a ladder from the cell Emerald leaves at the
              -- FOOT of a real staircase: Route 120's (22,77) is transition,
              -- climbs a course and a half to the terrace above, and draws no
              -- tread -- because the treads are in (22,76), which carries the
              -- ROM's own elevation 5 and is not in the chain at all.  It is
              -- metatile 1, sixteen rows of plain grass: `art = "surface"`,
              -- no wall anywhere in it, which is the generated table's way of
              -- saying nothing vertical is drawn here.  Lifted to the top of
              -- the climb it took the flight above it from a one-course rise
              -- to no rise at all (Route 120 flat flights 2 -> 3), so a chain
              -- with any such cell in it keeps the flight reading.  Fortree's
              -- ladder cells are 581 and 589, both `brow` -- rungs drawn down
              -- a vertical -- and both stay.
              --
              -- This can only ever move a chain whose gap is more than one
              -- course.  Over a 16px gap the clamp below already lands every
              -- cell on `hi` -- `lo + (a+1)*COURSE` is at least `lo+16` for
              -- a = 0 -- so Route 109's dunes, Lavaridge's lips, Lilycove's
              -- terrace edge and the Aqua Hideout's steps are byte-identical.
              -- Swept over all 518 maps: 130 transition chains that run
              -- between two levels at all, 50 of them with a tread drawn
              -- somewhere in them and 80 without; only 25 climb further than
              -- one course, and of those 13 are tread-less and just 9 also
              -- draw a face -- Fortree's five ladders and four cave-wall
              -- cells in Meteor Falls and Shoal Cave.
              local treads, flat = false, false
              if lo and hi and hi > lo then
                for _, c in ipairs(chain) do
                  local m2 = ctx.metatileAt(c[1], c[2])
                  if treadMeta(m2) then treads = true break end
                  local okA, a2 = pcall(ctx.metaRole, m2)
                  if not okA or a2 == nil or a2 == "surface" then
                    flat = true
                    break
                  end
                end
              end
              if lo and hi and hi > lo and not treads and not flat then
                -- ...AND ONLY A CLIMB OF MORE THAN ONE COURSE IS A FACE.
                -- Over a single course the two readings are the same answer,
                -- so the mark -- which takes the cell out of the terrain
                -- grade, and out of its neighbours' survey with it -- is
                -- withheld and 67 of the 80 tread-less chains in Hoenn are
                -- left exactly as they were.
                local drop = hi > lo + COURSE
                for _, c in ipairs(chain) do
                  rampCache[c[2] * 4096 + c[1]] = hi
                  if drop then faceRamp[c[2] * 4096 + c[1]] = true end
                end
              elseif lo and hi and hi > lo then
                -- how far each cell is from the bottom, and from the top
                local function spread(target)
                  local dist, queue, qi = {}, {}, 1
                  for _, c in ipairs(chain) do
                    for _, d in ipairs(NEIGHBOURS) do
                      local ne = ctx.elevationAt(c[1] + d[1], c[2] + d[2])
                      local nh = ne and elevHeight[ne] or nil
                      if nh == target and ne ~= ELEV_TRANSITION then
                        local k = c[2] * 4096 + c[1]
                        if dist[k] == nil then
                          dist[k] = 0
                          queue[#queue + 1] = c
                        end
                      end
                    end
                  end
                  while qi <= #queue do
                    local c = queue[qi]
                    qi = qi + 1
                    local dk = c[2] * 4096 + c[1]
                    for _, d in ipairs(NEIGHBOURS) do
                      local nx, ny = c[1] + d[1], c[2] + d[2]
                      local nk = ny * 4096 + nx
                      if dist[nk] == nil and passableRamp(nx, ny)
                         and seen[nk] then
                        dist[nk] = dist[dk] + 1
                        queue[#queue + 1] = { nx, ny }
                      end
                    end
                  end
                  return dist
                end
                local dLo, dHi = spread(lo), spread(hi)
                for _, c in ipairs(chain) do
                  local k = c[2] * 4096 + c[1]
                  local a, b = dLo[k], dHi[k]
                  if a and b then
                    -- ONE COURSE PER CELL OF THE RAMP, not a fraction of the
                    -- gap.  The old `t` placed every cell strictly inside the
                    -- gap, so a two-cell flight stood at a third and two
                    -- thirds of the way up -- heights on no course, meeting
                    -- no tread, drawn as a smooth slope with step art on it.
                    -- Victory Road's 54 non-course cells were all from here,
                    -- and its staircases read as texture painted on a floor.
                    --
                    -- `a` is how many cells up from the bottom this one is,
                    -- so a + 1 courses of climb is one block per step.  The
                    -- clamp keeps a flight longer than its own gap from
                    -- overshooting the tier it serves: it arrives flush and
                    -- the last cells are the landing.
                    local h = lo + (a + 1) * COURSE
                    if h > hi then h = hi end
                    rampCache[k] = h
                  end
                end
              end
            end
          end
        end
      end
    end
    return rampCache[cy * 4096 + cx]
  end

  -- IS THIS CELL A DRAWN FACE RATHER THAN GROUND?  True on the cells of a
  -- transition chain that climbs more than a course with no tread drawn
  -- anywhere in it -- Fortree's ladders.  Forces the ramp scan so the answer
  -- does not depend on whether `groundHeight` has been asked yet.
  function ctx.faceRampAt(cx, cy)
    if not elevHeight then return false end
    rampHeightAt(cx, cy)
    return (faceRamp and faceRamp[cy * 4096 + cx]) == true
  end

  function ctx.groundHeight(cx, cy)
    if not elevHeight then return 0 end
    local k = cy * 4096 + cx
    local hit = groundCache[k]
    if hit ~= nil then return hit end
    local e = ctx.elevationAt(cx, cy)
    local h
    if e == nil then
      h = 0
    elseif e == ELEV_TRANSITION then
      if ctx.blockedAt(cx, cy) then
        -- scenery: the datum, and `Structures` measures the rest off the art
        h = 0
      else
        h = rampHeightAt(cx, cy)
        if h == nil then
          -- not a ramp between two levels -- a lip, or a flat run of them:
          -- the lowest real level touching it, as before
          local best = nil
          for _, d in ipairs(NEIGHBOURS) do
            local ne = ctx.elevationAt(cx + d[1], cy + d[2])
            if ne and ne ~= ELEV_TRANSITION and ne ~= ELEV_MULTI then
              local nh = elevHeight[ne]
              if nh and (best == nil or nh < best) then best = nh end
            end
          end
          h = best or 0
        end
      end
    elseif e == ELEV_MULTI then
      -- A BRIDGE DECK, and how far over what it spans.
      --
      -- Emerald does not leave this to be guessed at either: the four bridge
      -- behaviours are an ORDERED height index (MetatileBehavior_GetBridgeType
      -- maps MB_BRIDGE_OVER_POND_LOW/MED/HIGH to 0/1/2), which is why Route
      -- 120 can carry a low bridge in its south and a high one in its north
      -- over the same pond.  So the lift comes from the behaviour, and one
      -- course is only the default.
      --
      -- Floored at the DATUM rather than at the neighbour: a bridge over the
      -- sea has nothing but surf-level cells around it, and surf sits BELOW
      -- the datum, so measuring from it would hang Route 110's cycling road
      -- fourteen pixels over the water it is supposed to soar across.
      local best = 0
      for _, d in ipairs(NEIGHBOURS) do
        local ne = ctx.elevationAt(cx + d[1], cy + d[2])
        if ne and ne ~= ELEV_MULTI and ne ~= ELEV_SURF then
          local nh = elevHeight[ne]
          if nh and nh > best then best = nh end
        end
      end
      local m = ctx.metatileAt(cx, cy)
      local lift = 1
      if m ~= nil then
        local b = ctx.attributes(m)
        lift = (ctx.bridgeLift and ctx.bridgeLift[b]) or 1
      end
      h = best + lift * COURSE
      -- A CAUSEWAY MAP measures everything from the drawing's own flat
      -- ground (see below), so its crossings measure from the datum too.
      if ctx.profile and ctx.profile.causeway then h = lift * COURSE end
    else
      h = elevHeight[e] or 0
      -- ROUTE 110 IS FLAT, AND ITS ELEVATION FIELD IS TRAFFIC CONTROL.
      --
      -- The map states two land levels, and its drawing states none: no
      -- cliff band anywhere, just a coastal plain with a flyover across
      -- it.  Elevation 4 is simply "belongs to the cycling road" -- the
      -- crossing logic needs the two roads on different levels -- so
      -- extruding it built a lawn-sided plateau under the road's north
      -- plaza, grass walls and all.  A map whose profile says `causeway`
      -- keeps its LAND on the datum and lets the BRIDGE behaviour carry
      -- all of the height: any deck cell stands at its stated lift over
      -- flat ground, wherever the elevation field put it.
      if ctx.profile and ctx.profile.causeway then
        if h > 0 then h = 0 end   -- the sea keeps its recess
        if m == nil then m = ctx.metatileAt(cx, cy) end
        if m ~= nil then
          local b = ctx.attributes(m)
          local lift = ctx.bridgeLift and ctx.bridgeLift[b]
          if lift then h = lift * COURSE end
        end
      end
    end
    groundCache[k] = h
    return h
  end

  -- --- what a cell IS ------------------------------------------------------
  --
  -- THE STRUCTURAL RULE, and the reason the behaviour table can be as short
  -- as it is.  Most of Hoenn is MB_NORMAL: a house wall, a tree trunk, a
  -- cliff face and the road in front of them all carry the same byte, because
  -- the byte answers "what kind of surface" and not "is this solid".  Three
  -- facts decide the rest, and Gen 3 states all three:
  --
  --   1. the BEHAVIOUR, where it has an opinion (water, grass, a ledge, a
  --      counter).  A stated answer always wins.
  --   2. the CELL's collision bit -- passability, which in Gen 3 lives on the
  --      map rather than on the tileset.
  --   3. the metatile's LAYER TYPE, which says whether its top half is drawn
  --      above the player.  Above-player art on a BLOCKED cell is cover: a
  --      treetop, a roof, the upper storey of a house.  That is the signal
  --      `Structures`' background flood spends its whole existence inferring
  --      from pixels on Gen 1 and Gen 2.
  --
  -- Passable cells keep their behaviour class even when they carry cover --
  -- that combination is tall grass you stand IN, or the shadowed cell under
  -- an overhang, and raising either one would put the player inside a box.
  local spec_ = ctx.spec
  local behaviour = spec_ and spec_.behaviour or {}
  local standing = spec_ and spec_.standing or {}
  local doorBehaviour = spec_ and spec_.doors or {}
  -- The four rail behaviours.  They sit on WALKABLE cells -- the rail runs
  -- along the edge of the walkway and stops you leaving sideways, not walking
  -- it -- so the `standing` rule below would otherwise flatten every one of
  -- them into ground, and they drew as a painted stripe lying in the floor.
  local railBehaviour = {
    [0xD3] = true,   -- MB_ISOLATED_VERTICAL_RAIL
    [0xD4] = true,   -- MB_ISOLATED_HORIZONTAL_RAIL
    [0xD5] = true,   -- MB_VERTICAL_RAIL
    [0xD6] = true,   -- MB_HORIZONTAL_RAIL
  }

  -- ---------------------------------------------------------------------
  -- SCENERY THE BEHAVIOUR BYTE DOES NOT NAME.
  --
  -- Built once per map, lazily, because it needs NEIGHBOURS and `classAt`
  -- only ever sees one cell. Emerald's border forest is not a tree drawing
  -- with a silhouette around it -- it is a 2x2-metatile motif tiled edge to
  -- edge across whole columns of the map (468/469 over 476/477 in Littleroot,
  -- the same shape in every other town's palette). Read cell by cell that is
  -- a green wall, and a green wall is what the mesher built: the "trees are a
  -- tiled green mass" in the report.
  --
  -- Read as a TILING it is a stand of trees, and the right un-projection is
  -- one round crown per 2x2 block -- which is what `canopy` means to
  -- `Structures.buildCylinders`: a 32px hull carved over four cells, anchored
  -- at the top-left, its partners marked `cylinder`. Tiled across a forest
  -- that gives a field of overlapping crowns instead of a hedge, and a lone
  -- tree in a garden gets a single 16px hull rather than a box.
  --
  -- Row-major greedy is deliberately the whole algorithm. It anchors at the
  -- top-left of every mass, which is where Emerald's own motif starts, and a
  -- mass with an odd width or height simply ends in single-cell crowns --
  -- correct-looking either way, and no alignment to guess at.
  -- THE BORDER RING COUNTS. A Gen 3 map is surrounded by its border patch
  -- tiled outward, and in Hoenn that patch is almost always the SAME forest
  -- motif as the map's own edge -- which is most of the trees anybody
  -- actually sees, because the ring is what fills the horizon. Scanning only
  -- 0..width-1 left every one of them a flat green box standing beside the
  -- round crowns inside the map, which reads worse than if neither had been
  -- carved. `blockedAt` answers solid off the map and `metatileAt` border-
  -- extends, so the same rules work out here with no special case.
  local RING = 8            -- cells beyond the body, matching Structures' ring
  -- the cartridge's own behaviour->class table, for the fallback guard
  local behaviourNames = (spec() or {}).behaviour
  local scenery = nil
  -- HOW MANY CELLS ACROSS THE HULL AT AN ANCHOR IS.
  --
  -- 2 for Emerald's ordinary tree -- four quarters of one crown -- and 3 for
  -- the big one Mossdeep draws beside it (see the square test below).
  -- `Structures.buildCylinders` reads it through `ctx.scenerySpan` and sizes
  -- the round template to match.  Declared here beside `scenery` on purpose:
  -- a local declared AFTER the closure that uses it is a global inside it,
  -- and that has silently aborted three passes in this file under pcall.
  local sceneryScale = nil
  -- WHICH ANCHORS STAND ON A CELL ANOTHER TREE ALREADY CLAIMED.  Mossdeep
  -- draws trees that share a cell (see the overlap rule in `buildScenery`),
  -- and `Structures.buildCylinders` has to be told that such an anchor is a
  -- tree of its own rather than a partner it has already consumed.  Declared
  -- here beside `scenery` for the reason given above: a local declared AFTER
  -- the closure that uses it is a global inside it.
  local sceneryShared = nil
  local function buildScenery()
    scenery = {}
    sceneryScale = {}
    sceneryShared = {}
    if width <= 0 or height <= 0 then return end
    local art = Gen3.analyse(map.tileset)
    if not art then return end

    local x0, y0 = -RING, -RING
    local x1, y1 = width + RING - 1, height + RING - 1
    local stride = x1 - x0 + 1
    local function idx(cx, cy) return (cy - y0) * stride + (cx - x0) end

    local function leafAt(cx, cy)
      if cx < x0 or cy < y0 or cx > x1 or cy > y1 then return false end
      -- off the map, solidity is a fact about the art (see classAt)
      if not ctx.offMap(cx, cy) and not ctx.blockedAt(cx, cy) then
        return false
      end
      local m = ctx.metatileAt(cx, cy)
      if m == nil then return false end
      -- a PINNED metatile has been spoken for by a profile and is not up for
      -- reinterpretation here
      if ctx.pins and ctx.pins[m] then return false end
      local st = art.stats[m]
      if not (st and st.leafy and st.solid > 0.5) then return false end
      -- ...AND HOENN DRAWS EVERY LEAF IN GREEN.
      --
      -- `leafy` is a reading of TEXTURE -- a mottled, high-frequency fill --
      -- and volcanic ash has exactly that texture.  Route 112's metatile 790
      -- is a rock brow, the drawn top edge of an ash bank, and it read leafy
      -- on all 22 of its cells: twenty-two lengths of terrace rim built as
      -- round bushes standing in the middle of the ash field.
      --
      -- The role table already carries what the thing is DRAWN IN, and no
      -- tree, hedge or bush in the region is drawn in anything but green.
      -- Measured with the guard on, across all 518 maps: 22 cells change,
      -- every one of them 790 on Route 112, and no map loses a tree.
      local okM, _, material = pcall(ctx.metaRole, m)
      if okM and material ~= nil and material ~= "green" then return false end
      return true
    end

    -- ----------------------------------------------------------------
    -- A CROWN YOU WALK BEHIND IS STILL PART OF THE TREE.
    --
    -- MOTIVATED BY MOSSDEEP CITY'S TREES -- (31..34, 5..6), the pair on the
    -- lawn north of the Space Centre, and the big one at (42..44, 12..14).
    --
    -- `leafAt` above begins "if it is not blocked it is not foliage", and
    -- that is a statement about COLLISION, not about the drawing.  Emerald
    -- draws a tree the way `buildGen3Lamps` says it draws a lamp: the crown
    -- goes on the ABOVE-PLAYER layer and you walk behind it, so the crown's
    -- cells are walkable and only the trunk row underneath is blocked.  On
    -- the Mossdeep pair that is 794/795 over 802/803 and on the big tree
    -- 762/763/772 over 778/779/780 over 786/787/788 -- and of those eleven
    -- metatiles `leafAt` accepted exactly TWO (802, 803).  The result is the
    -- report: "the mossdeep trees" are two 16px pills lying on the grass with
    -- the crown printed flat on the ground above them.
    --
    -- The cartridge states which layer it drew on and `analyse` already
    -- measures it: `leafFrac` is how much of the drawn cell is foliage and
    -- `leafFrac2` how much of that was carried on the above-player layer.
    -- Read across the Mossdeep pair the two numbers are the same statistic
    -- twice and the ratio is bimodal with nothing in between:
    --
    --   794 795 762 763 772 778 779 780 854 853   leafFrac2 / leafFrac = 1.00
    --   802 803 786 788 787                       leafFrac2 / leafFrac = 0.00
    --
    -- The first list is crown, the second is trunk and root.  Counted in
    -- CELLS the split is total: of the 227 cells on Mossdeep that wear a
    -- leafy green metatile, 93 read 0.00 and 134 read 1.00 and NOTHING reads
    -- anything else.  Region-wide over the 81 outdoor maps, of 25,124 such
    -- cells 15,601 read below 0.2 and 9,095 read 0.9 or more -- 98.1% in the
    -- two tails, 478 cells between them.  This is the same shape of reading
    -- the last several rounds turned on (the border patch's rock test, the
    -- roof plan's row interior, the stair run's width).
    --
    -- A crown is claimed ONLY as part of a complete square (below).  A lone
    -- one is never stood up on its own, because the other thing Hoenn draws
    -- on the above-player layer in green is the FRINGE under a tree wall --
    -- gTileset_General's 14/15/29, 118 cells of one repeated metatile along
    -- Route 123 -- which is the underside of the mass above it and not an
    -- object standing in the field.
    local function crownAt(cx, cy)
      if cx < x0 or cy < y0 or cx > x1 or cy > y1 then return false end
      local m = ctx.metatileAt(cx, cy)
      if m == nil then return false end
      if ctx.pins and ctx.pins[m] then return false end
      local st = art.stats[m]
      if not (st and st.leafy) then return false end
      local lf, lf2 = st.leafFrac or 0, st.leafFrac2 or 0
      if not (lf2 > 0.5 and lf2 >= lf * 0.9) then return false end
      local okM2, _, material2 = pcall(ctx.metaRole, m)
      return (okM2 and material2 == "green") or false
    end

    -- ...AND THE FOOT IS THE HALF OF THE TREE THAT STOPS YOU.
    --
    -- The bottom row of Mossdeep's big tree is 786/787/788: root spray, the
    -- trunk, root spray.  It is blocked, it is drawn in green, and it is
    -- drawn on the PLAYER'S OWN layer -- which is the same reading as the
    -- crown with the ratio the other way round.  `leafAt` rejects all three:
    -- 786 and 788 are only 41% inked (a root spray over open grass, under
    -- `leafAt`'s `solid > 0.5`) and 787 is 49% leaf (mostly bark, under
    -- `analyse`'s `leafy`).  Without them the tree's own foot is meshed as
    -- two blocks of masonry with a cliff face between them.
    -- ...AND ONLY THE TOP OF A TREE ANCHORS ONE.
    --
    -- The other thing Hoenn draws in above-player green is the FRINGE along
    -- the bottom of a tree WALL -- gTileset_General's 14/15/29, the leaves
    -- that hang over the path you walk under.  It is the underside of the
    -- mass above it, not an object standing in the field, and a hull
    -- anchored there is a crown carved out of the wrong two rows: measured
    -- with the fringe let in, Route 119 grew 34 new anchors, Route 120
    -- twenty, the Battle Frontier eighteen, and the region's sunken-cell
    -- count went 49 -> 59 as the terrace vote lost the ground under them.
    --
    -- What tells the two apart is what is drawn ABOVE: a tree's crown has
    -- sky over it and a fringe has more tree.  So a crown may JOIN a square
    -- anywhere (Mossdeep's 854/853 carry one tree's crown over the next
    -- one's trunk and are the right-hand half of the pair at (31..32, 5..6))
    -- but it may only ANCHOR one where nothing leafy stands over it.
    local function crownTop(cx, cy)
      if not crownAt(cx, cy) then return false end
      return not (leafAt(cx, cy - 1) or crownAt(cx, cy - 1))
    end

    local function footAt(cx, cy)
      if cx < x0 or cy < y0 or cx > x1 or cy > y1 then return false end
      if not ctx.offMap(cx, cy) and not ctx.blockedAt(cx, cy) then
        return false
      end
      local m = ctx.metatileAt(cx, cy)
      if m == nil then return false end
      if ctx.pins and ctx.pins[m] then return false end
      local st = art.stats[m]
      if not st then return false end
      local lf, lf2 = st.leafFrac or 0, st.leafFrac2 or 0
      if not (lf > 0.25 and lf2 <= lf * 0.1) then return false end
      local okM2, _, material2 = pcall(ctx.metaRole, m)
      return (okM2 and material2 == "green") or false
    end

    local claimed = {}
    for cy = y0, y1 do
      for cx = x0, x1 do
        local i = idx(cx, cy)
        if not claimed[i] and (leafAt(cx, cy) or crownTop(cx, cy)) then
          local ie, is, id = idx(cx + 1, cy), idx(cx, cy + 1), idx(cx + 1, cy + 1)
          -- a square anchored on a blocked leaf is Emerald's tiled wood and
          -- keeps exactly the members it always had; only a square anchored
          -- on the TOP OF A CROWN may take in the cells you walk behind
          local anchorTop = crownTop(cx, cy)
          -- ...AND HOENN DRAWS TREES AT TWO SIZES.
          --
          -- MOTIVATED BY MOSSDEEP CITY.  The user's two frames are the two
          -- drawings: `mossdeep_trees_small.png` is a pair of crowns 32px
          -- across and `mossdeep_tree_big.png` one crown 48px across, and
          -- measured off the cartridge's own art the ratio is exactly 1.5 --
          -- the small tree is 2x2 metatiles (794/795 over 802/803) and the
          -- big one 3x3 (762/763/772 over 778/779/780 over 786/787/788).
          -- Collapsing them to one size draws the wrong tree twice.
          --
          -- The big tree states its own shape and it is not a threshold:
          -- TWO ROWS OF CROWN OVER ONE ROW OF FOOT, nine cells, and nine
          -- DIFFERENT metatiles.  That last clause is what keeps a forest
          -- out of it -- Emerald tiles a wood out of a handful of repeated
          -- metatiles (Route 112's border band is 445 cells of one), so a
          -- tiled mass can never present nine distinct cells in a square,
          -- and the same reasoning the 2x2 `motif` test below is written on
          -- carries the 3x3 unchanged.
          --
          -- Region-wide over the 81 outdoor maps this square forms on
          -- Mossdeep City and its tileset-mates and nowhere else.
          local nine, nk = false, nil
          if anchorTop and cx + 2 <= x1 and cy + 2 <= y1 then
            nine, nk = true, {}
            local seenM = {}
            for dy = 0, 2 do
              for dx = 0, 2 do
                local j = idx(cx + dx, cy + dy)
                nk[#nk + 1] = j
                if claimed[j] then nine = false end
                local mm = ctx.metatileAt(cx + dx, cy + dy)
                if mm == nil or seenM[mm] then nine = false
                else seenM[mm] = true end
                if dy < 2 then
                  if not crownAt(cx + dx, cy + dy) then nine = false end
                elseif not footAt(cx + dx, cy + dy) then
                  nine = false
                end
              end
            end
          end
          if nine then
            for _, j in ipairs(nk) do
              claimed[j] = true
              scenery[j] = "cylinder"
            end
            scenery[i] = "canopy"
            sceneryScale[i] = 3
            goto placed
          end
          -- AND THE 2x2 HAS TO BE A 2x2 DRAWING.
          --
          -- Emerald's standard tree is four DIFFERENT metatiles -- the four
          -- quarters of one crown, 468/469 over 476/477 in Littleroot -- so
          -- reading a block of them as one 32px crown is un-projecting a
          -- drawing.  Dewford's thicket is not that: it is a single metatile
          -- (579) tiled over the whole island, one small bush with its own
          -- trunk per cell.  Grouped in fours it became a field of 32px
          -- crowns twice the size of anything drawn, which is the "trees in
          -- Dewford should be rendered differently" report.  A repeated
          -- metatile is a hedge and gets one small hull per cell.
          local mA = ctx.metatileAt(cx, cy)
          local mB = ctx.metatileAt(cx + 1, cy)
          local mC = ctx.metatileAt(cx, cy + 1)
          local motif = mA ~= nil and mB ~= nil and mC ~= nil
                        and mA ~= mB and mA ~= mC
          -- ...AND A QUARTER OF IT MAY BE A CROWN YOU WALK BEHIND.  Same
          -- drawing, same square; only the collision differs (see `crownAt`).
          -- ...AND A TREE STANDS ON ITS OWN FOOT.
          --
          -- Anchoring on the top of a crown is still not enough on its own.
          -- Route 119's forest is 198/199 -- blocked, but drawn ENTIRELY on
          -- the above-player layer (leafFrac2 0.98), so it is crown by every
          -- reading -- and where the fringe metatile 14 stands at its
          -- north-west corner with open ground over it, a 2x2 formed out of
          -- one fringe cell and three cells of tree WALL.  That is a corner
          -- of a wood, not a tree.
          --
          -- A tree has a FOOT: a bottom row drawn on the player's own layer,
          -- with the trunk and the root spray on it (Mossdeep 802/803 and
          -- 786/787/788; the General tileset's 22/23 under 198/199).  A wall
          -- has none -- it is crown all the way down to the fringe.  So the
          -- widened square must have at least one foot cell along its bottom
          -- row.  Measured over the 81 outdoor maps this is what keeps the
          -- change inside the Mossdeep tileset.
          local widen = anchorTop
                        and (footAt(cx, cy + 1) or footAt(cx + 1, cy + 1))
          local function quarterAt(qx, qy)
            return leafAt(qx, qy) or (widen and crownAt(qx, qy))
          end
          -- A CROWN MAY ONLY ANCHOR A SQUARE IT IS THE TREE OF.  Where the
          -- anchor is not foliage in its own right -- a walkable crown --
          -- the square must be a whole tree: crown on top, foot underneath.
          -- Without this clause Route 119's fringe cell at (36,26) anchored
          -- a 32px crown over three cells of tree WALL.
          local four = motif and cx < x1 and cy < y1
                       and (leafAt(cx, cy) or widen)
                       and quarterAt(cx + 1, cy) and quarterAt(cx, cy + 1)
                       and quarterAt(cx + 1, cy + 1)
                       and not claimed[ie] and not claimed[is]
                       and not claimed[id]
          if four then
            claimed[i], claimed[ie], claimed[is], claimed[id] =
              true, true, true, true
            scenery[i] = "canopy"
            scenery[ie] = "cylinder"
            scenery[is] = "cylinder"
            scenery[id] = "cylinder"
            sceneryScale[i] = 2
          elseif leafAt(cx, cy) then
            -- A LONE CROWN IS NOT AN OBJECT.  Only a cell that is blocked
            -- foliage in its own right falls back to a hull of its own; an
            -- above-player crown that formed no square is the underside of
            -- something else (Route 123's fringe) and is left as it was
            -- drawn.
            claimed[i] = true
            scenery[i] = "cylinder"
          end
        end
        ::placed::
      end
    end

    -- ...AND TWO TREES MAY STAND IN THE SAME CELL.
    --
    -- MOTIVATED BY MOSSDEEP CITY (28..30, 21..23) -- two crowns drawn one
    -- over the other's foot -- and the three-tree cluster at (31..34, 5..7).
    -- Reported as "trees in mossdeep that are near other trees arent fully
    -- rendering both, if you can make them both render ... or allow them to
    -- overlap".
    --
    -- Emerald packs its trees closer than a cell grid can hold.  At (29,22)
    -- metatile 853 is ONE tree's left foot with the NEXT tree's right crown
    -- composited over it; 854/853 at (32..33, 6) is a whole crown drawn
    -- across two other trees' feet.  The claim above is a row-major greedy
    -- over an EXCLUSIVE grid, so the first tree to reach a shared cell takes
    -- it and the second forms no square at all: it falls through to the
    -- lone-cell branch and keeps the two 16px pills of its foot row, which
    -- reads as a pair of green lozenges lying on the grass beside a proper
    -- crown.
    --
    -- The un-projection the drawing states is that the hulls OVERLAP, the
    -- way the crowns do in 2D.  A cell may therefore belong to more than one
    -- claim.  `Structures.buildCylinders` already accepts a partner that is
    -- `cylinder` OR `canopy`, so an anchor standing on another tree's
    -- partner costs nothing there.
    --
    -- WHAT KEEPS A WOOD OUT OF IT is that the square must be a WHOLE TREE --
    -- crown over crown, foot over foot, four distinct metatiles -- and that
    -- the PHASE IS READ OFF THE FEET.  A crown row composites (853 is crown
    -- and foot at once) and a foot row does not, so a tree's two feet are
    -- the pair, counted from the west end of the run of feet they lie in.
    -- Without that, [795,794] -- the right half of one crown beside the left
    -- half of the next -- reads as a tree and carves a hull out of two
    -- neighbours (Mossdeep (23,14)); and the 3x3 big tree's own middle row
    -- reads as a small one, which the pairing refuses because its foot run
    -- is THREE cells (786/787/788) and an odd run has no pairing.
    --
    -- Measured over the 81 outdoor maps this claims NINE squares on FIVE
    -- maps -- Mossdeep 5, Routes 110, 115, 119 and 120 one each -- and
    -- nothing at all on the tiled woods the exclusivity gate was protecting:
    -- Route 123, Route 112, Petalburg, Dewford and the Safari Zone are
    -- unchanged.
    for cy = y0, y1 - 1 do
      for cx = x0, x1 - 1 do
        local i = idx(cx, cy)
        local ie, is = idx(cx + 1, cy), idx(cx, cy + 1)
        local id = idx(cx + 1, cy + 1)
        -- never displace a hull that already exists: only a PARTNER cell may
        -- be shared, never another tree's anchor
        local whole = scenery[i] ~= "canopy" and scenery[ie] ~= "canopy"
                      and scenery[is] ~= "canopy" and scenery[id] ~= "canopy"
                      and crownAt(cx, cy) and crownAt(cx + 1, cy)
                      and footAt(cx, cy + 1) and footAt(cx + 1, cy + 1)
        if whole then
          local seenM = {}
          for _, c in ipairs({ { cx, cy }, { cx + 1, cy },
                               { cx, cy + 1 }, { cx + 1, cy + 1 } }) do
            local mm = ctx.metatileAt(c[1], c[2])
            if mm == nil or seenM[mm] then whole = false
            else seenM[mm] = true end
          end
        end
        if whole then
          local rs, re = cx, cx + 1
          while footAt(rs - 1, cy + 1) do rs = rs - 1 end
          while footAt(re + 1, cy + 1) do re = re + 1 end
          if (re - rs + 1) % 2 ~= 0 or (cx - rs) % 2 ~= 0 then whole = false end
        end
        -- a square that overlaps NOTHING is one the greedy already refused
        -- for a reason of its own; this rule is only about the cell two
        -- trees share
        if whole and (claimed[i] or claimed[ie] or claimed[is]
                      or claimed[id]) then
          claimed[i], claimed[ie] = true, true
          claimed[is], claimed[id] = true, true
          scenery[i] = "canopy"
          for _, j in ipairs({ ie, is, id }) do
            if scenery[j] ~= "canopy" then scenery[j] = "cylinder" end
          end
          sceneryScale[i] = 2
          -- ...and say so, because `Structures.buildCylinders` suppresses a
          -- cell an earlier group consumed and has to be told this one is an
          -- anchor in its own right.  Nothing else may pass that gate.
          sceneryShared[i] = true
        end
      end
    end

    -- A BOULDER IS A ROCK STANDING IN A FIELD, NOT A PIECE OF CLIFF.
    --
    -- Route 111's desert is scattered with big rounded rocks, and Emerald
    -- draws each one exactly the way it draws a tree: four DIFFERENT
    -- metatiles making the four quarters of one round object -- 587/588 over
    -- 144/146 at (18..19, 42..43) -- with smaller ones as single cells.  Read
    -- cell by cell they are `cliff`, so every boulder in the desert meshed as
    -- a square block of masonry sitting on the sand, and the same drawing
    -- appears on the terraces and cliff tops all over Hoenn.
    --
    -- The un-projection is the one already written above for a crown: a 2x2
    -- motif becomes one 32px hull anchored at the top-left with its partners
    -- marked `cylinder`, a lone one a 16px hull.  Same rule, different
    -- material.
    --
    -- What separates a boulder from a CLIFF is not its art -- both are drawn
    -- in rock and both read `brow` and `face` in the role table -- it is that
    -- a boulder is a LUMP.  A cliff band runs for hundreds of cells; a
    -- boulder's whole blocked component is four cells, or five where a pebble
    -- touches it.  So the component is flooded with a hard stop, and anything
    -- that does not terminate inside it is landscape and left alone.
    local LUMP_MAX = 9        -- cells; a 2x2 boulder, a pebble or two beside it
    -- ...AND A ROCK IN THE SEA IS NOT A BOULDER IN A FIELD.
    --
    -- The lone-cell branch below reads a small lump with a drawn top as a
    -- rock, and the sea routes are full of those: Route 126's dive spots
    -- alone put eleven new hulls in the water, each one meshed a course under
    -- the surface it stands in (`class=cylinder src=skip h=28 lowest
    -- neighbour=44`).  Standing a rock out of water is `buildGen3Water`'s
    -- job and it already does it.  This is about rocks on the GROUND.
    local function onLand(cx, cy)
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = cx + d[1], cy + d[2]
        if not ctx.offMap(nx, ny) and not ctx.blockedAt(nx, ny) then
          local okR, r = pcall(ctx.roleAt, nx, ny)
          if okR and r ~= "water" then return true end
        end
      end
      return false
    end
    local function rocky(cx, cy)
      if cx < x0 or cy < y0 or cx > x1 or cy > y1 then return false end
      if scenery[idx(cx, cy)] then return false end
      if ctx.offMap(cx, cy) then return false end
      if not ctx.blockedAt(cx, cy) then return false end
      local m = ctx.metatileAt(cx, cy)
      if m == nil then return false end
      if ctx.pins and ctx.pins[m] then return false end
      local st = art.stats[m]
      if not (st and (st.solid or 0) > 0.5) then return false end
      if st.overhead then return false end
      if leafAt(cx, cy) then return false end
      return true
    end
    -- the lump this cell belongs to, or nil if it runs past LUMP_MAX
    local lumpMemo = {}
    local function lump(cx, cy)
      local key = cy * 8192 + cx
      local hit = lumpMemo[key]
      if hit ~= nil then return hit or nil end
      local seen, q, qh = { [key] = true }, { { cx, cy } }, 1
      while qh <= #q do
        local c = q[qh]; qh = qh + 1
        if #q > LUMP_MAX then
          for k2 in pairs(seen) do lumpMemo[k2] = false end
          return nil
        end
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = c[1] + d[1], c[2] + d[2]
          local nk = ny * 8192 + nx
          if not seen[nk] and rocky(nx, ny) then
            seen[nk] = true
            q[#q + 1] = { nx, ny }
          end
        end
      end
      for k2 in pairs(seen) do lumpMemo[k2] = q end
      return q
    end
    for cy = y0, y1 do
      for cx = x0, x1 do
        local i = idx(cx, cy)
        if not claimed[i] and rocky(cx, cy) and lump(cx, cy) then
          local ie, is, id = idx(cx + 1, cy), idx(cx, cy + 1), idx(cx + 1, cy + 1)
          local mA = ctx.metatileAt(cx, cy)
          local mB = ctx.metatileAt(cx + 1, cy)
          local mC = ctx.metatileAt(cx, cy + 1)
          local motif = mA ~= nil and mB ~= nil and mC ~= nil
                        and mA ~= mB and mA ~= mC
          -- ...AND A BOULDER HAS A DRAWN TOP.
          --
          -- The lump test alone lets a small CLIFF outcrop through -- four
          -- cells at the corner of a bank are a lump too -- and wrapping a
          -- vertical rock face round a cylinder reads as a pale striped disc
          -- lying on the sand, which is what the first cut of this put in
          -- Route 111's desert.  Emerald draws a boulder's upper row as a
          -- BROW, a cap with face rows under it, exactly as it draws the top
          -- of anything you see the top of; a cliff corner is `face cap 0`
          -- all the way up, because you never see over it.
          -- ...AND ONE HULL PER CELL, NOT ONE PER 2x2.
          --
          -- The leaf pass un-projects a four-metatile crown into a single
          -- 32px hull and the first cut of this did the same for rock.  In
          -- the frame it is wrong, and the role table says why: the desert's
          -- 587/588 carry `cap 8`, so the rock's drawn top turns over HALFWAY
          -- DOWN the upper cells and the eight rows above it are sand.  A
          -- 32px canvas takes those rows, the alpha carve does not cut them,
          -- and the boulder meshes as a drum with a pale sandy lid -- "the
          -- 2x2 rocks in the desert are showing the sand on top".  A tree's
          -- crown carries `cap 16`, a full drawn top, which is why the same
          -- canvas works there.
          --
          -- Per cell the canvas is that cell's own drawing and the carve is
          -- exact.  A four-cell rock comes out as four quarter-domes reading
          -- as one lumpy mound, and every three-cell lump on the mesa --
          -- which could never form a square at all -- gets the same
          -- treatment.  Both were in the same shot: the lone hulls read as
          -- rocks, the 2x2 hulls read as drums.
          -- A 2x2 LUMP IS ONE ROCK AND GETS ONE HULL.
          --
          -- Hoenn's big boulders are drawn the way its trees are: four
          -- DIFFERENT metatiles making the four quarters of one object.  The
          -- lumps measure exactly that -- 587/588 over 144/146 seven times in
          -- Route 111's desert, 131/132 over 139/140, 163/164 over 171/172 --
          -- so the un-projection is one 32px hull over the four cells, a
          -- per-pixel solid of revolution of the whole drawing.
          --
          -- Cut per cell instead for one revision and it reads as four
          -- quarter-domes in a heap; the shot showed it at once.  The
          -- per-cell branch below is for the lumps that are NOT a square --
          -- the mesa's 105/105/190 lying in a single row -- which can never
          -- form one and were meshing as masonry.
          local capA = select(3, ctx.metaRole(mA))
          local mB2 = ctx.metatileAt(cx + 1, cy)
          local mC2 = ctx.metatileAt(cx, cy + 1)
          local capB2 = select(3, ctx.metaRole(mB2))
          local four = mA ~= nil and mB2 ~= nil and mC2 ~= nil
                       and mA ~= mB2 and mA ~= mC2
                       and cx < x1 and cy < y1
                       and (capA or 0) > 0 and (capB2 or 0) > 0
                       and rocky(cx + 1, cy) and rocky(cx, cy + 1)
                       and rocky(cx + 1, cy + 1)
                       and not claimed[ie] and not claimed[is]
                       and not claimed[id]
                       and #(lump(cx, cy) or {}) <= 6
                       and onLand(cx, cy)
          if four then
            claimed[i], claimed[ie], claimed[is], claimed[id] =
              true, true, true, true
            scenery[i] = "canopy"
            scenery[ie] = "cylinder"
            scenery[is] = "cylinder"
            scenery[id] = "cylinder"
          elseif (capA or 0) > 0 and #(lump(cx, cy) or {}) <= 4
             and onLand(cx, cy) then
            -- ...AND A ROCK THAT IS NOT A 2x2 IS STILL A ROCK.
            --
            -- The 2x2 branch un-projects Emerald's four-quarter drawing, and
            -- Hoenn does not draw every rock that way: the mesa above Route
            -- 111's desert is scattered with THREE-cell lumps (105 at (22,25),
            -- 226 at (17,42), 131 at (8,86)) that cannot form a square, so
            -- every one of them stayed a block of masonry while the four-cell
            -- rocks on the sand below became hulls -- reported as the rocks on
            -- the terrace above not being raised or cylindrical at all.
            --
            -- Same answer the leaf pass gives a lone bush: one 16px hull for
            -- the cell.  Still inside the lump test, and still only where the
            -- art draws a TOP, so a cliff corner is not swept in.
            --
            -- FOUR CELLS, not the nine the lump test allows.  A boulder is a
            -- lump of one to four; a five-to-nine lump is more often a scrap
            -- of cliff that happens to stand alone, and at nine Sootopolis
            -- turned a hundred cells of crater stone into pills.
            claimed[i] = true
            scenery[i] = "cylinder"
          end
        end
      end
    end

    -- A SIGN IS A BOARD ON A POST, NOT A BLOCK OF MASONRY.
    --
    -- Emerald's town signs, route signs, mailboxes and notice boards are
    -- single blocked cells standing alone in the open, drawn face-on: a panel
    -- with lettering, seen from the front. The behaviour byte does not name
    -- them (MB_NORMAL, like everything else) and their collision makes them
    -- `wall`, so each one meshed as a full-depth cube of signboard -- which
    -- is the "signs are boxy" report.
    --
    -- What identifies them is not their art but their ISOLATION: one blocked
    -- cell with open ground on every side is not a piece of a building, it is
    -- an object standing in a field. `signpost` gives it the billboard
    -- treatment -- the drawing cut out per pixel and stood up two voxels
    -- thin -- which is what a board on a post actually is.
    --
    -- Foliage is excluded because it has already been claimed as a hull, and
    -- anything with above-player art is excluded because that is a structure
    -- you walk behind rather than a panel you read.
    local function lone(cx, cy)
      if cx < x0 or cy < y0 or cx > x1 or cy > y1 then return false end
      if scenery[idx(cx, cy)] then return false end
      local solid
      if ctx.offMap(cx, cy) then return false end
      if not ctx.blockedAt(cx, cy) then return false end
      local m = ctx.metatileAt(cx, cy)
      if m == nil then return false end
      if ctx.pins and ctx.pins[m] then return false end
      local st = art.stats[m]
      if not st then return false end
      if st.leafy or st.overhead or st.overhang then return false end
      -- a panel is DRAWN, not a sliver of ground poking through
      if st.solid < 0.4 then return false end
      -- ISOLATION, WITH ONE EXCEPTION: THE WALL BEHIND IT.
      --
      -- Requiring all four neighbours open is right for a sign in the middle
      -- of a field and wrong for most of the ones Emerald actually places:
      -- a town sign stands directly in FRONT of the building it names, so
      -- its north neighbour is that building's wall. Every such sign failed
      -- this test, stayed a `wall` cell, and meshed as a 16px box wearing its
      -- board on the front face and again flat on the lid -- the sign outside
      -- Birch's lab drawn twice, and in Dewford swallowed whole into the
      -- house's column.
      --
      -- East, west and south must still be open -- that is what makes it an
      -- object rather than a piece of the building -- and the cell behind
      -- must be a DIFFERENT metatile, so a wall's own corner or a porch
      -- returning north cannot pass.
      local m0 = ctx.metatileAt(cx, cy)
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 } }) do
        local nx, ny = cx + d[1], cy + d[2]
        if nx >= 0 and ny >= 0 and nx < width and ny < height
           and ctx.blockedAt(nx, ny) then
          return false
        end
      end
      if ctx.blockedAt(cx, cy - 1) then
        local mn = ctx.metatileAt(cx, cy - 1)
        if mn == nil or mn == m0 then return false end
      end
      return true
    end
    -- OUTDOORS ONLY. A lone blocked cell in a field is a sign; a lone blocked
    -- cell in a bedroom is furniture, and calling it a signpost stood May's
    -- bed up as a thin board on a stick in the corner of her room.
    if ctx.outdoor then
      for cy = 0, height - 1 do
        for cx = 0, width - 1 do
          if lone(cx, cy) then scenery[idx(cx, cy)] = "signpost" end
        end
      end
    end

    -- A ROCK STANDING IN THE SEA.
    --
    -- Emerald draws one as a 2x2 block: a small grey boulder in the middle
    -- with the water disturbed around it, and it marks all four cells
    -- impassable because you cannot surf onto a rock.  Read as collision
    -- that is a two-cell-square wall, and the mesher stood the whole thing
    -- up -- ripple and all -- as a blue mound with the boulder painted on
    -- its face.  What is actually there is flat sea with a rock in it.
    --
    -- So the cells stay WATER, which is what the sea around them is, and the
    -- rock is remembered here for `Structures.buildWaterRocks` to stand up as
    -- a hull over them.  The test is the surroundings: a 2x2 of blocked
    -- MB_NORMAL cells with nothing but water on all twelve sides of it is not
    -- a piece of coastline or a jetty, it is a rock.
    -- ...and OFF THE MAP DOES NOT COUNT AGAINST IT.  Rustboro's north-west
    -- rocks sit in the corner of the body with the sea running off the edge
    -- past them, and the border patch out there is forest, not sea -- so a
    -- ring test that demanded water on all twelve sides failed on exactly the
    -- rocks the report is about.  Outside the body there is no answer, so
    -- take none: the ring is what the MAP says around it.
    local function waterCell(cx, cy)
      if cx < 0 or cy < 0 or cx >= width or cy >= height then return true end
      local m = ctx.metatileAt(cx, cy)
      if m == nil then return false end
      return behaviourNames[ctx.attributes(m)] == "water"
    end
    local function rockCell(cx, cy)
      if cx < 0 or cy < 0 or cx >= width or cy >= height then return false end
      if not ctx.blockedAt(cx, cy) then return false end
      local m = ctx.metatileAt(cx, cy)
      if m == nil or (ctx.pins and ctx.pins[m]) then return false end
      -- MB_NORMAL, or one of the ground-ish bytes Emerald hands solid art:
      -- what is excluded is a cell the ROM names as something in particular
      -- (a ledge, a waterfall, a door), because that is not a rock.
      local bn = behaviourNames[ctx.attributes(m)]
      if bn ~= nil and bn ~= "ground" and bn ~= "grass" then return false end
      local st = art.stats[m]
      -- drawn, and not foliage: a bush in a pond is still a bush
      return (st and st.solid > 0.4 and not st.leafy and not st.overhead)
             and true or false
    end
    ctx.waterRocks = {}
    if ctx.outdoor then
      for cy = 0, height - 2 do
        for cx = 0, width - 2 do
          if rockCell(cx, cy) and rockCell(cx + 1, cy)
             and rockCell(cx, cy + 1) and rockCell(cx + 1, cy + 1)
             and not scenery[idx(cx, cy)] then
            -- ...AND A ROCK MAY HAVE ANOTHER ROCK BESIDE IT.  Emerald sets
            -- these in pairs and clusters, so demanding water on all twelve
            -- sides rejected every rock that had a neighbour -- which is most
            -- of them off Route 105.  What matters is that the group stands
            -- in open water, not that it stands alone: most of the ring must
            -- be sea, and anything else in it has to be more rock.
            local ringed, sea = true, 0
            for _, d in ipairs({ { -1, -1 }, { 0, -1 }, { 1, -1 }, { 2, -1 },
                                 { -1, 0 }, { 2, 0 }, { -1, 1 }, { 2, 1 },
                                 { -1, 2 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }) do
              local nx, ny = cx + d[1], cy + d[2]
              if waterCell(nx, ny) then
                sea = sea + 1
              elseif not rockCell(nx, ny) then
                ringed = false
                break
              end
            end
            if sea < 7 then ringed = false end
            if ringed then
              for dy = 0, 1 do
                for dx = 0, 1 do
                  scenery[idx(cx + dx, cy + dy)] = "water"
                end
              end
              ctx.waterRocks[#ctx.waterRocks + 1] = { cx, cy }
            end
          end
        end
      end
    end

    -- A RAIL IS NOT A WALL.
    --
    -- Outdoors the carve separates these as cleanly as it separates furniture
    -- indoors, and for the same reason: a wall's art fills its cell, while a
    -- fence, a rail, a chain-link run or a low kerb is a thin thing with the
    -- ground showing through and around it. Measured on Rustboro, whose
    -- streets are lined with them, the rails carve to 0.19-0.26 solid against
    -- a wall's 1.00 -- four fifths of the cell is ground -- and every one of
    -- them was meshing as a full-depth block sixteen pixels through.
    --
    -- Foliage and anything with above-player art are excluded: a hedge is a
    -- hull and an awning is a structure, and both can be thin.
    -- A RAILING STANDS ON GROUND.  A ROCK RIDGE IS THE GROUND'S EDGE.
    --
    -- The carve above is necessary and not sufficient.  Sootopolis is paved
    -- in white stone and its crater ridges are drawn as olive bands winding
    -- over that paving; the band's colour is also a ground sample, so the
    -- ridge carves to the same fifth of a cell a Rustboro rail does.  492
    -- cells of the town -- metatiles 721/728/730/731/732/736/738 -- meshed as
    -- railings and stood across every street in the low-angle shot.
    --
    -- The drawing separates them without ambiguity.  A rail is an object ON a
    -- surface, so its cell still draws that surface: measured over the game's
    -- outdoor tilesets, every rail with more than a handful of cells --
    -- Rustboro's 792/793/538, Slateport's 322/320/307, Mauville's 690/689,
    -- Verdanturf's 846/944/803 -- is `surface` art with a cap of 12 to 16 and
    -- NO front face.  A ridge, a brow or a bank has no cap at all (cap 0 or 1)
    -- and a face of 2 to 16, because it IS relief rather than something
    -- standing on it.
    -- ...AND NOT WHERE THE CARTRIDGE HAS ALREADY NAMED THE ROCK.
    --
    -- The pixel test above is a statement about a THIN thing with ground
    -- showing round it, and `solid` is measured against the map's own floor
    -- colour -- so a cell drawn IN that floor's colours reads thin because it
    -- IS the floor.  Route 114's and Route 115's rock tops are exactly that:
    -- gTileset_Fallarbor's 577, 572, 571, 569 and 595 are pale speckled stone
    -- on pale speckled ground, `surface` art with cap 16 and no face, and they
    -- measure solid 0.09 to 0.32 -- inside the railing window, and cap 16 /
    -- face 0 passes the cap test trivially.
    --
    --     Route114  843 cells of 577 alone, 675 of the map's 3,200
    --     Route115  363 cells
    --     1,038 cells region-wide, on those two maps and no others
    --
    -- Meshed as `fence` each one is a 10px THIN slab with the ground left
    -- showing round it (TileShape.THIN), so the mountain is a field of low
    -- bars you see daylight between rather than a mass -- the same twelve
    -- cells g3-sculpt-220 found cut clean through the ridge at (36,29) and
    -- (37,28).
    --
    -- The cartridge settles it in one byte.  MB_MOUNTAIN_TOP is Emerald's own
    -- word for the top of a rock mass; not one railing in Hoenn carries it,
    -- and every rail this carve exists for -- Rustboro's 792/793/538,
    -- Slateport's 322/320/307, Mauville's 690/689 -- is MB_NORMAL.
    --
    -- In-game location: Route 114's north-west and north-east rock flanks and
    -- the ridges of Route 115.
    -- MAUVILLE'S LOG FENCE IS ONE OBJECT AND THIS GATE CUTS IT IN FOUR.
    -- (g3-rank-263 -- measured against the user's own 2D/3D pair of
    -- MauvilleCity and NOT shipped.  Read this before widening the gate.)
    --
    -- The cartridge draws the property line round MauvilleCity's Game Corner
    -- as one log fence, and every arm of it is the SAME 8px round-topped
    -- post repeated -- TWO POSTS PER GEN 3 CELL, one per tile, which is the
    -- five-instance "a cell is two tile rows and two tile columns" trap.
    -- Metatile 650/648 (the north-south arms) draw the post twice down the
    -- cell, exactly 8px-periodic (`rows2` = 5,5,5,5,7,8,7,6 twice over);
    -- 657 (the east-west arms) draws it twice ACROSS, columns 1..6 and 9..14
    -- identical; 689/690 are the same drawing with the last post given its
    -- base row, and 640/642 the same with a cap.
    --
    -- One fence, and it leaves this file as FOUR classes:
    --
    --   657   E-W arms   solid 0.40  cap 5 face 3   -> cliff    h 32
    --   650   N-S arms   solid 0.38  cap 16 face 0  -> wall     h 16
    --   689   end post   solid 0.29  cap 16 face 0  -> fence    h 10
    --   690   end post   solid 0.29  cap 16 face 0  -> fence    h 26
    --   642   cap post   solid 0.51  cap 5 face 3   -> cylinder h 16
    --
    -- 648/650 and 689/690 have BYTE-IDENTICAL role rows -- surface, green,
    -- cap 16, face 0, motif true -- and are 4-connected in a straight line.
    -- The only thing between them is `solid`, 0.38 against this carve's
    -- `< 0.35`, and the frame shows what that costs: the north-south arms
    -- fall to `wall`, `foundGen3Buildings` gives them a run, and each arm
    -- draws as ONE CONTINUOUS 16px STRIP down the property line with the
    -- `cylinder` cap sitting on its end as a round disc -- "a felled log".
    -- The east-west arms are claimed by the sprite carve instead and come
    -- out RIGHT, a march of separate posts, from the same drawing.
    --
    -- WIDENING THE GATE IS NOT THE FIX, twice over.  0.35 -> 0.40 is fitting
    -- a constant to two metatiles, which this project does not do; and
    -- `fence` would not repair the frame anyway -- `TileShape.ART.fence` is
    -- `upright`, a box, so the arm would still be a strip, only 10 or 26px
    -- tall instead of 16.  A fence that reads as posts needs the drawing's
    -- 8px unit to become the drawn unit, and nothing in this file works at
    -- 8px.  That is the next reading, and it is a class, not a threshold.
    --
    -- MEASURED, so the obvious worry can be dismissed: MauvilleCity's 95
    -- `cylinder` cells are NOT the fence.  87 are trees (metatiles 198, 22,
    -- 14, 199 -- role `tree`, leafy, solid 0.78..1.00), 6 are the round
    -- bushes along the path (664/666, spaced two cells apart), and exactly
    -- TWO are fence: the north caps 640 and 642.  The fence can never
    -- become 95 lathes.
    --
    -- AND THE FENCE CANNOT BE REPAIRED BY MAKING ITS RUN ONE CLASS EITHER.
    -- (g3-railrun-264 -- measured over all 518 maps and NOT shipped.)
    --
    -- The tempting invariant is "a 4-connected run of blocked cells with a
    -- byte-identical role row should share a class", since 648/650 (`wall`)
    -- and 689/690 (`fence`) have identical rows and are in one straight
    -- line.  Hoenn violates it 618 times on 134 maps, over 31,230 cells,
    -- with run lengths from 2 to 3,978 and no mode anywhere -- and only 29
    -- of those runs involve a fence at all.
    --
    -- A ROLE ROW IS ABOUT THE MATERIAL AND A CLASS IS ABOUT THE OBJECT;
    -- data/gen3_metatiles.lua says so in its own header ("Asked of a
    -- metatile, 'is this a cliff' has no answer").  The three rows doing
    -- nearly all the merging are `surface/water/0/0` -- Underwater Route
    -- 128's whole 3,978-cell seabed -- `face/rock/0/16` -- Ever Grande's
    -- 1,331-cell rock -- and `surface/green/16/0//true`, which is EVERY
    -- TREE AND EVERY FENCE POST in the general tileset at once.  The
    -- commonest split of the 618 is `canopy` against `cylinder`, 243 runs
    -- and 12,749 cells, and that is exactly the distinction g3-crown-242
    -- and g3-lathe-250 exist to make.
    --
    -- Nor can the winner be ordered from the role table: 27 runs carry
    -- three classes or four (MtPyre_Exterior, 1,041 cells, is
    -- cliff/signpost/wall/water in ONE run).  Take the majority and the
    -- winner is `cylinder` on 229 runs and `cliff` on 175 against `fence`
    -- on 9 -- and MauvilleCity's own fence run is 32 cells of which 28 are
    -- TREES, so this property line would come out as a row of lathes.
    --
    -- Measured separately, because it is the thing worth knowing: even a
    -- PERFECT class here does not un-weld the fence.  With the carve
    -- widened so the whole north-south arm resolves to `fence`, every cell
    -- takes the same height and the arm is one continuous box again --
    -- vertical surface 1,614 -> 2,670 px^2 on the (6,14..18) arm, 1,224 ->
    -- 2,824 on (14,12..18).  A taller strip, not posts.  The welding is
    -- adjacent equal-height boxes; the run founding is not the culprit and
    -- refusing `foundGen3Buildings` a run on a `fence` line would be a
    -- no-op, since no `fence` cell in the 81 outdoor maps carries one.
    -- The fence needs the drawing's 8px unit to become the drawn unit, and
    -- that is a class, not a classifier tweak.
    --
    -- ...AND THAT CLASS WAS DESIGNED, MEASURED AND REFUSED TOO.
    -- (g3-post-265.  Two independent reasons; read both before trying it.)
    --
    -- FIRST, THE UNIT CANNOT BE DERIVED WITHOUT LEAKING.  The exact test --
    -- the cell's post-carve opaque mask splits into two identical 8px halves
    -- on exactly one axis, neither half empty nor full -- fires on 409
    -- metatiles over 3,395 cells across all 72 tilesets: 280 of them `wall`,
    -- 56 `cliff`, 15 `tabletop`, 12 `cylinder`, and only 11 `fence`.
    -- Interior art is drawn in 8px modules, so shelf fronts, window bands
    -- and railings all qualify.  Nothing separates them: the fill fraction
    -- of the 409 runs 0.008 to 0.984 in a smooth ramp, `wall` spans the
    -- whole of it, and the fences (0.188 .. 0.328) sit inside the wall
    -- range with wall metatiles at 0.062, 0.125, 0.188, 0.250, 0.312 and
    -- 0.344 interleaved among them.  Conjoining `railStands` does not save
    -- it either -- metatile 657, the one arm of Mauville's fence that
    -- currently draws RIGHT, fails `railStands` on `face = 3`.
    --
    -- SECOND, AND WORSE: ON THE AXIS THAT IS BROKEN THE 8PX UNIT IS NOT A
    -- POST.  Read off the carved atlas, the two arms of the same fence:
    --
    --   657, east-west, ALREADY CORRECT     650, north-south, THE DEFECT
    --     row  4 |..###.....###...|           row  0 |.........#####..|
    --     row  9 |.#####...#####..|           row  5 |........########|
    --     row 14 |..###.....###...|           row 11 |.........#####..|
    --     cols   0 9 11 11 11 9 0 0 ...       cols   0 x8 4 16 16 16 16 16 8 4
    --
    -- 657 has THREE FULLY EMPTY COLUMNS between its two posts and four
    -- fully empty rows above them: each 8px column is one whole post with
    -- background all round it, which is exactly why the per-pixel sprite
    -- carve already draws that arm as a march of posts.  650 is ONE
    -- UNBROKEN BAR -- columns 9..13 occupied in all sixteen rows -- and its
    -- 8px period is post-tops EMBOSSED on a continuous rail.  Emerald draws
    -- a receding fence that way because you cannot see between posts that
    -- stand one behind another.
    --
    -- So there is nothing in the north-south drawing to cut on.  g3-rank-263
    -- established that a rank is periodic only where there is BACKGROUND
    -- between its units; the east-west arm has that background and the
    -- north-south arm has none.  Slicing the bar into 8px units and standing
    -- each at its own depth would be inventing the gaps, which is the
    -- four-instance "a drawing smeared over a box that was resized" failure
    -- in its purest form.
    --
    -- ...AND ROUTE 117 SHOWS WHAT RIGHT LOOKS LIKE, WHICH CHANGES THE ANSWER.
    -- (g3-postrun-266.  Read this before acting on the paragraph above.)
    --
    -- Route117 draws the same fence CORRECTLY out of this same tileset, and
    -- the reason is neither positional nor a recovered 8px unit.  It is a
    -- different METATILE landing on the other side of this carve's own
    -- ceiling:
    --
    --   Route117 north-south fence  320 / 322  solid 0.328  -> `fence`
    --   Mauville north-south fence  648 / 650  solid 0.375  -> `wall`
    --
    -- `classAt` answers identically for the same metatile on both maps (648
    -- is `wall` on Route 117 too), so nothing about the town is doing this.
    -- What the miss COSTS is a run: 648/650 fall to `wall`, a run is founded
    -- over them (n=30 f=35 h=16 at Mauville (6,15..17)), and `heightAt`
    -- reads the run before the shape.  Measured on the fence cells alone:
    --
    --   Route117 (8,14..16)  fence, no run   30 horiz quads, 90 vert / 2,572 px^2
    --   Mauville (6,15..17)  wall + run      12 horiz quads, 14 vert /   130 px^2
    --
    -- 130 px^2 of standing surface for three cells of fence is the flat
    -- brown strip in the report.  And 320/322 are the SAME UNBROKEN BAR as
    -- 650 -- columns 2..5 occupied in all sixteen rows -- so the paragraph
    -- above stands: the correct rendering is not obtained by cutting an 8px
    -- unit, because Route 117 has no 8px unit either.
    --
    -- CORRECTION TO g3-railrun-264: its probe (this ceiling widened to 0.45)
    -- was read as "one class welds into a taller strip" off a window that
    -- included the terrain beside the fence.  On the fence cells alone the
    -- probe moves Mauville TOWARDS Route 117 -- 12 -> 30 horizontal quads,
    -- which is Route 117's figure exactly, one top face per drawn cell
    -- instead of one run drawn once, and 130 -> 1,074 px^2 of standing
    -- surface.  The measurement was right; the conclusion drawn from it was
    -- not, and it would have sent the next reader away from the answer.
    --
    -- WHAT STILL BLOCKS IT is this ceiling and nothing else.  Every exact
    -- derivation of it from the drawing leaks: "a wholly empty 8px half-cell
    -- AND the drawing repeating at 8px on the other axis", the tightest form
    -- there is, admits 132 metatiles over 1,182 cells -- 72 `wall` and 26
    -- `cliff` against 11 `fence`, including building corners at solid 0.996
    -- and 1.000.  And 0.35 -> 0.45 is a constant fitted to two metatiles.
    -- The gate wants a statement about what a RAIL is that `solid` is not
    -- making.  TWO CANDIDATES HAVE NOW BEEN MEASURED AND BOTH FAIL
    -- (g3-rail-267); do not re-derive them.
    --
    -- ASYMMETRY RATHER THAN DENSITY.  320 and 650 are mirror images -- a
    -- dense 8px half and a wholly empty one -- so 0.328 and 0.375 are the
    -- same drawing at two offsets and any ceiling between them cuts a line
    -- that is not there.  The right shape of statistic is therefore the
    -- RATIO of the fuller 8px half to the emptier, and over all 5,056
    -- blocked metatiles it is genuinely bimodal, with a true gap:
    --
    --     1.00-1.25 2953   2-4 547   8-16 55   64-999   0
    --     1.25-2     860   4-8 131   16-64 13  INFINITE 390
    --
    -- Nothing between 16 and infinity.  It still cannot be used: the 390
    -- with an exactly-empty half cover 3,485 cells and are wall 176,
    -- cliff 91, water 42, FENCE 32, ledge 23 -- cliff edges and ledges,
    -- with rails at eight percent -- and their fill fractions overlap
    -- completely (fence 0.094..0.328 inside wall 0.004..0.500).  A
    -- statistic can be bimodal and still select the wrong thing.
    --
    -- (And a correction to g3-postrun-266, which reported wall leakers "at
    -- solid 0.996", impossible for a metatile with an empty half: it printed
    -- `Gen3.analyse`'s TILESET-level `solid` beside a mask taken from
    -- `Gen3.shapeDataForMap`'s PER-MAP carve.  Two surfaces.  On one surface
    -- the empty-half population tops out at fill 0.500 exactly.)
    --
    -- REFUSING THE RUN RATHER THAN RECLASSIFYING.  The damage is the run,
    -- not the class, so the smaller claim is "a cell whose metatile has a
    -- wholly empty 8px half may not found a building run".  Enumerated over
    -- all 518 maps: 3,169 run-carrying tiles on 165 maps would lose one --
    -- wall 2,585, cliff 453, shell 118 -- led by MagmaHideout_4F 245,
    -- MagmaHideout_1F 171, NewMauville_Inside 153, Underwater_Route128 99,
    -- AquaHideout_B1F 89, SootopolisCity 69 (51 of them crater cliff) and
    -- LilycoveCity_ContestHall 37.  MauvilleCity's fence is 16 of the 3,169.
    -- Half the caves and hideouts in Hoenn lose their walls to repair one
    -- property line.
    --
    -- WHAT WOULD ACTUALLY WORK is a MODEL rather than a carve: a fence line
    -- stated as posts (`buildFigures`-style, the machinery that already
    -- matches authored SHAPES per tileset) with the rail drawing used as
    -- TEXTURE rather than as silhouette.  That is an authoring job, not a
    -- classifier, and it is the only reading left standing.
    local function railStands(m)
      if ctx.attributes(m) == MB_MOUNTAIN_TOP then return false end
      local okR, _, _, cap, face = pcall(ctx.metaRole, m)
      if not okR then return false end
      return (tonumber(cap) or 0) >= 1 and (tonumber(face) or 0) <= 1
    end
    -- WHERE THE LINE GOES, AND WHY IT IS DRAWN AT A CAP OF ONE.
    --
    -- The obvious threshold is the one the real rails sit at -- cap 12 to 16
    -- -- but Sootopolis' Mart is painted in blues the lake also uses, so the
    -- analyser reads its roof (metatiles 619/620/621) as 8% drawn, `brow`,
    -- cap 1, face 1.  That is character for character the ridge metatile 721,
    -- and no pixel statistic separates them.  A cap of 12 throws the shop's
    -- roof out with the ridges and the Mart meshes as a pale slab.
    --
    -- So the line is drawn at "has ANY cap and draws no face": it keeps every
    -- real rail (Rustboro 792/793 cap 16, 538 cap 12, 800 cap 1; Slateport
    -- 322/320 cap 16; Mauville 689/690 cap 16), keeps the Mart, and still
    -- takes 412 of Sootopolis' 492 false railings -- 728, 730, 731, 732, 736
    -- and 738, every one of them cap 0 with a face of 2 to 16.  721 is the
    -- one ridge piece that survives, and it survives because the cartridge
    -- draws it exactly like a shop roof.

    if ctx.outdoor then
      for cy = 0, height - 1 do
        for cx = 0, width - 1 do
          local i = idx(cx, cy)
          if not scenery[i] and ctx.blockedAt(cx, cy) then
            local m = ctx.metatileAt(cx, cy)
            if m and not (ctx.pins and ctx.pins[m]) then
              local st = art.stats[m]
              if st and st.solid > 0.06 and st.solid < 0.35
                 and not st.leafy and not st.overhead and not st.overhang
                 and railStands(m) then
                scenery[i] = "fence"
              end
            end
          end
        end
      end
    end


    -- INDOOR FURNITURE, from the floor showing around it.
    --
    -- A room's blocked cells are the walls AND everything standing in it, and
    -- the behaviour byte separates none of them: 94% of every indoor blocked
    -- cell in the game resolved to generic `wall`, which is why the tables,
    -- the PCs and the televisions were all boxes.
    --
    -- The carve separates them, and the reason it can is simple: a WALL fills
    -- its cell -- there is no floor to see past it -- while a table, a chair,
    -- a television or a plant is an object standing ON the floor, so the
    -- floor shows around it and the cell carves partly away. That is the
    -- whole test, and it needs this map's own floor to work (see
    -- Gen3.shapeDataForMap).
    --
    -- Which WAY the object is drawn decides its shape, and Emerald states
    -- that too. Art on the above-player layer is drawn face-on and standing
    -- against a wall -- a television, a PC, a bookcase, a fridge -- so it
    -- becomes an upright whose picture is its FRONT face, which is what puts
    -- a screen on the front of the box instead of lying on its lid. Art with
    -- nothing above the player is a surface seen from above -- a table, a
    -- counter, a bed -- and rides the top face at table height.
    if not ctx.outdoor then
      -- FURNITURE IS A DISCRETE OBJECT; A WALL IS A RUN.
      --
      -- The carve alone is not enough. A room's back wall is decorated --
      -- panelling, a window, a poster -- and some of that decoration is drawn
      -- in colours the floor also uses, so the wall carves partly away and
      -- reads like an object standing on the floor. Taken cell by cell, the
      -- Pokemon Center's entire fourteen-cell north wall came out as a row of
      -- tables.
      --
      -- What separates them is EXTENT. A table, a plant, a television, a bin
      -- is a handful of cells with floor all around it; a wall is a long
      -- connected run that lines the room. So the furniture rule only applies
      -- inside a small blocked blob, and the walls -- which are the big ones
      -- -- stay walls.
      local FURNITURE_MAX = 8
      local blob, seenBlob = {}, {}
      for cy = 0, height - 1 do
        for cx = 0, width - 1 do
          local root = cy * width + cx
          if not seenBlob[root] and ctx.blockedAt(cx, cy) then
            local stack, cells = { { cx, cy } }, {}
            seenBlob[root] = true
            while #stack > 0 do
              local c = table.remove(stack)
              cells[#cells + 1] = c
              for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local nx, ny = c[1] + d[1], c[2] + d[2]
                local k = ny * width + nx
                if nx >= 0 and ny >= 0 and nx < width and ny < height
                   and not seenBlob[k] and ctx.blockedAt(nx, ny) then
                  seenBlob[k] = true
                  stack[#stack + 1] = { nx, ny }
                end
              end
            end
            local n = #cells
            for _, c in ipairs(cells) do blob[c[2] * width + c[1]] = n end
          end
        end
      end
      for cy = 0, height - 1 do
        for cx = 0, width - 1 do
          local i = idx(cx, cy)
          local size = blob[cy * width + cx]
          if not scenery[i] and size and size <= FURNITURE_MAX
             and ctx.blockedAt(cx, cy) then
            local m = ctx.metatileAt(cx, cy)
            local pinned = m and ctx.pins and ctx.pins[m]
            -- THIS RULE IS A FALLBACK, NOT AN OVERRIDE. Where the behaviour
            -- byte already names the thing -- a television, a PC, a shop
            -- counter, a bookcase all have their own MB_ value -- that answer
            -- is the cartridge's and beats anything inferred from pixels.
            -- Without this guard, loosening the rule turned Brendan's games
            -- console (stated, MB_TELEVISION) into a coffee table.
            local named = false
            if m then
              local b = ctx.attributes(m)
              local bc = behaviourNames and behaviourNames[b]
              named = bc ~= nil and bc ~= "ground" and bc ~= "wall"
            end
            if m and not pinned and not named then
              local f = Gen3.solidForMap(map, m)
              local st = art.stats[m]
              -- a real object leaves floor around it, and is not a sliver
              if f and f > 0.12 and st then
                scenery[i] = (st.n2 > 0) and "prop" or "tabletop"
              end
            end
          end
        end
      end
    end

    ctx.sceneryIndex = idx
  end

  -- A ROOF, which Emerald states more plainly than any other object it draws.
  --
  -- Its layer type puts the top half ABOVE the player -- that is what makes
  -- you walk behind a house -- and it fills the cell, so a blocked metatile
  -- with a nearly full above-player layer is a surface seen FROM ABOVE with a
  -- building under it. Nothing else in an outdoor tileset looks like that
  -- except foliage, and foliage is leafy and has already been claimed.
  --
  -- Not a class, deliberately. Calling these cells `roof` would mark them
  -- authored, which takes them OUT of the region flood -- and then the house
  -- is two cells of wall with a rug of roof art lying on the grass beside it.
  -- What the volume builder actually needs is the count: how many tile rows
  -- at the top of this column are roof. It already splits a facade from a
  -- pitched roof that way; on Gen 1 it has to guess the split from repeats in
  -- the art, and here it can simply be told.
  function ctx.roofAt(cx, cy)
    -- OUTDOORS ONLY. Above-player art indoors is the top of a wall, a
    -- doorframe, a shelf -- priority, not a pitched roof over a facade, and
    -- reading it as one puts a gable on the kitchen units.
    if not ctx.outdoor then return false end
    if not ctx.blockedAt(cx, cy) then return false end
    local m = ctx.metatileAt(cx, cy)
    if m == nil then return false end
    if ctx.pins and ctx.pins[m] then return false end
    if ctx.sceneryAt(cx, cy) then return false end
    local art = Gen3.analyse(map.tileset)
    local st = art and art.stats[m]
    if not st then return false end
    return (st.overhead and st.solid > 0.75 and not st.leafy) and true or false
  end

  function ctx.sceneryAt(cx, cy)
    if scenery == nil then
      local okS = pcall(buildScenery)
      if not okS then scenery = {} end
    end
    -- the scenery grid spans the BORDER RING as well as the body, so it has
    -- its own index rather than the map's
    local idx = ctx.sceneryIndex
    if not idx then return nil end
    return scenery[idx(cx, cy)]
  end

  -- How many CELLS across the hull anchored here is -- 2 for Emerald's
  -- ordinary tree, 3 for the big one Mossdeep draws.  nil everywhere the
  -- scenery carve placed no anchor.  (See `sceneryScale` in buildScenery.)
  function ctx.scenerySpan(cx, cy)
    if scenery == nil then
      local okS = pcall(buildScenery)
      if not okS then scenery = {} sceneryScale = {} end
    end
    local idx = ctx.sceneryIndex
    if not (idx and sceneryScale) then return nil end
    return sceneryScale[idx(cx, cy)]
  end

  -- True where the scenery carve stood a tree on a cell another tree had
  -- already claimed -- MOSSDEEP CITY (28..30, 21..23) and its cluster at
  -- (31..34, 5..7).  nil everywhere else, and on every map that carves no
  -- overlapping tree at all.
  function ctx.sceneryShared(cx, cy)
    if scenery == nil then
      local okS = pcall(buildScenery)
      if not okS then scenery = {} sceneryScale = {} sceneryShared = {} end
    end
    local idx = ctx.sceneryIndex
    if not (idx and sceneryShared) then return nil end
    return sceneryShared[idx(cx, cy)]
  end

  function ctx.classAt(cx, cy, metatile)
    local m = metatile
    if m == nil then m = ctx.metatileAt(cx, cy) end
    if m == nil then return nil end

    -- A PINNED METATILE OUTRANKS EVERYTHING, and is reported as pinned so the
    -- shape can be marked authored.
    --
    -- This is the only way to say "that cell is a fridge". The behaviour byte
    -- cannot: every kitchen unit, every chair, every table and the wall behind
    -- them is MB_NORMAL, because the byte answers what KIND OF SURFACE a cell
    -- is and furniture is not a kind of surface. The layer type cannot either
    -- -- it separates walls from furniture in most of a room but not all of
    -- it, and a rule that flattens a few wall cells is worse than no rule.
    --
    -- So interiors are hand-pinned per tileset, the way the Gen 1 and Gen 2
    -- profiles pin tile ids. A Gen 3 metatile id is stable within its tileset,
    -- and the profile is keyed by the tileset's pokeemerald NAME.
    local pin = ctx.pins and ctx.pins[m]
    if pin then return pin, true end

    -- SCENERY, read off the art and its neighbours (see buildScenery above).
    -- Above the cache on purpose: this answer is a property of the CELL --
    -- which tree in which stand -- and not of the metatile, so the metatile
    -- cache below would hand the same crown to every cell in the forest.
    local scene = ctx.sceneryAt(cx, cy)
    -- ...BUT NOT OVER A LEDGE, WHICH THE CARTRIDGE NAMES AND THE CARVE
    -- CANNOT SEE.
    --
    -- A ledge is drawn as a thin band with ground showing above and below it,
    -- which is character for character what the carve looks for in a railing:
    -- Route 114's west-facing ledge is sixteen cells of MB_JUMP_WEST and every
    -- one of them came back `fence`, so the map grew a railing down a slope
    -- instead of a step you hop.  Route 123 lost five more to `signpost` and
    -- Route 112 four to `cylinder`.
    --
    -- The two are not the same object in 3D.  A fence stands ON flat ground;
    -- a ledge IS the change in ground -- a one-course drop with a direction,
    -- and the direction is stated (MB_JUMP_EAST/WEST/NORTH/SOUTH and the four
    -- diagonals).  Nothing the carve can measure recovers that, so where the
    -- cartridge names a ledge the carve does not get to answer.
    -- ...AND NOT OVER A BUILDING, EITHER.
    --
    -- The railing carve looks for a thin band of art on an otherwise open cell
    -- -- "solid between 0.06 and 0.35" -- and the top row of a Pokemon Mart's
    -- roof is exactly that shape: Sootopolis' 619, 620 and 621 measure 0.06 to
    -- 0.12, so the shop's own roof came back `fence` and was meshed as a bar
    -- on a post.  Petalburg's Mart, drawn from the same general-tileset art
    -- but with a roof row the carve does not reach, meshes as a building --
    -- which is the difference reported between the two.
    --
    -- A cell the warp machinery has already claimed for a building is part of
    -- that building, whatever its art looks like from above.  Guarded against
    -- re-entry for the same reason as the landscape rule below: buildings ->
    -- roofAt -> sceneryAt -> the carve -> here.
    if scene and not ctx.inSceneClass then
      ctx.inSceneClass = true
      local okB, isB = pcall(ctx.isBuildingCell, cx, cy)
      ctx.inSceneClass = nil
      if okB and isB then scene = nil end
    end
    if scene then
      local bScene = ctx.attributes(m)
      local rowScene = bScene ~= nil and behaviour[bScene] or nil
      if rowScene ~= "ledge" then return scene, true end
    end

    -- OFF THE MAP THERE IS NO COLLISION, ONLY ART.
    --
    -- `blockedAt` answers solid for anything outside the body, and it is right
    -- to: you cannot walk off the edge of a Hoenn map. But that is a statement
    -- about where the player may stand, and out here it is the only statement
    -- there is -- so every map whose border patch is ordinary GRASS grew a
    -- solid wall right around itself, a 16px lip running the full width of the
    -- world just past the last row. On Petalburg that is the green ribbon
    -- floating behind the houses.
    --
    -- The border patch is drawn art like any other, and the shape surface says
    -- exactly how much of a cell is object rather than ground. Out here, use
    -- that: a border of lawn is lawn, a border of forest is still forest.
    local blocked
    if ctx.offMap(cx, cy) then
      local artB = Gen3.analyse(map.tileset)
      local stB = artB and artB.stats[m]
      blocked = (stB and stB.solid > 0.5) and true or false
    else
      blocked = ctx.blockedAt(cx, cy)
    end
    -- ELEV_MULTI IS THE CARTRIDGE SAYING "DECK", AND IT IS A FACT ABOUT
    -- THE CELL, NOT ABOUT THE METATILE.
    --
    -- 15 means "do not change the walker's elevation here", which is what a
    -- bridge is; Emerald uses it for nothing else.  Most decks also carry a
    -- bridge BEHAVIOUR and reach `bridge` that way, but plenty do not --
    -- Victory Road's thirty crossings are ordinary floor metatiles whose
    -- only statement of deck is the elevation.  A ground cell is a column
    -- standing on the world; a bridge cell is a span with daylight under
    -- it, and that difference is the whole of "the bridges aren't
    -- floating": the crossings were solid plinths of rock with planks
    -- printed on the lid.
    --
    -- ABOVE THE CACHE, and never written to it.  The class cache is keyed
    -- on `m * 2 + blocked` -- the METATILE, not the cell -- so any per-cell
    -- rule placed after the lookup is unreachable the moment that same
    -- metatile has been asked about anywhere else on the map.  These decks
    -- are drawn in the floor's own metatiles, so the answer was always
    -- already cached as `ground` and the rule never once ran.
    --
    -- EVERY MAP, not just the caves this was written for.  On Routes 110
    -- and 120 and in Fortree it changes nothing -- those decks already
    -- reach `bridge` through their behaviour byte.  Route 119 is the one
    -- that moves: its six river crossings are 22 cells that state ONLY
    -- elevation, and they measured ragged, 52 at the ends and 36 in the
    -- middle -- the same mid-air step Victory Road had.  It ships with the
    -- levelling pass, which is what makes them one flat surface, and with
    -- the under-span plate guarantee, which is what stops the daylight
    -- underneath becoming a hole.
    if not blocked and ctx.elevationAt(cx, cy) == ELEV_MULTI then
      return "bridge"
    end

    -- ELEVATION 1 IS WATER, AND THE ROM SAYS SO.
    --
    -- Emerald reserves elevation 1 for the surf datum -- it is what the game
    -- tests to decide whether you are on a Pokemon's back -- and the height
    -- field already recesses it below the shore.  But the CLASS was still
    -- coming from the behaviour byte, and a handful of Mossdeep's shore cells
    -- carry an ordinary MB_NORMAL: they resolved to `ground` sitting at the
    -- water's own datum, a strip of lawn two pixels under the sea with a
    -- four-course headland behind it.
    --
    -- ABOVE THE CACHE, AND IT WRITES NOTHING -- which is the same lesson the
    -- ELEV_MULTI rule above it already paid for.  Elevation is a property of
    -- the CELL and the cache is keyed on the METATILE, so sitting below the
    -- lookup this rule answered for whichever cell happened to be asked
    -- first: on Route 128, 35 walkable surf cells of metatile 108 came back
    -- `ground` because a cell of 108 at elevation 0 had been asked earlier,
    -- while 103 cells of metatile 113 on the same map, at the same elevation
    -- and equally walkable, came back `water`.  Which answer a cell got
    -- depended on scan order, and both were cached as if they were facts
    -- about the tile.
    --
    -- ...EXCEPT A WATERFALL.  A fall is surf-level by exactly this logic --
    -- you ride up one on a Pokemon's back, so Emerald marks it elevation 1
    -- -- and is the one surf cell in the game that is not a horizontal plane.
    --
    -- ...AND EXCEPT A DECK, which is the other thing elevation 1 means.  A
    -- bridge sits at surf level precisely BECAUSE you surf underneath it; the
    -- elevation is the water's, not the deck's.  Route 110's cycling road is
    -- 46 walkable cells of MB_BRIDGE_OVER_OCEAN at elevation 1, and all 46
    -- came back `water`: the road was drawn as the sea it crosses.
    if not blocked and ctx.elevationAt(cx, cy) == ELEV_SURF then
      local bSurf = ctx.attributes(m)
      local rowSurf = bSurf ~= nil and behaviour[bSurf] or nil
      if rowSurf == "waterfall" then return "waterfall" end
      if rowSurf ~= "bridge" and rowSurf ~= "log" then return "water" end
    end

    -- LANDSCAPE ROCK IS NOT A BUILT WALL, AND THE MESHER TREATS THEM
    -- DIFFERENTLY.
    --
    -- Applied at BOTH exits, because the cache below is keyed by metatile and
    -- this correction is a property of the CELL: the same white stone is a
    -- building wall where a door stands under it and a crater terrace twenty
    -- cells away.  Putting it only after the cache write meant the first call
    -- for a metatile was corrected and every call after it read `wall` back
    -- out of the cache -- 108 pits before the change and 108 after.
    local function asLandscape(cls, cx2, cy2)
      if cls ~= "wall" or ctx.inRoleClass then return cls end
      -- OUTDOORS ONLY.  Indoors there is no landscape: every blocked mass is
      -- built, and `roleAt` has no warp standing under a kitchen wall to
      -- recognise it by, so it answers `shelf` and this would turn the room
      -- into a cliff.  Caught by gen3_interior_test -- "the unit's upper door
      -- stays part of the wall: got cliff want wall".
      if not ctx.outdoor then return cls end
      ctx.inRoleClass = true
      local okR, r = pcall(ctx.roleAt, cx2, cy2)
      ctx.inRoleClass = nil
      -- A FENCE IS LANDSCAPE.  It is drawn and meshed as the rock it
      -- is -- the whole point of the role is that it stops being a
      -- terrace BOUNDARY, not that it stops being rock.  Left out,
      -- every pen wall in the Safari Zone would keep the built
      -- `wall` class and change material in the frame.
      if okR and (r == "cliff" or r == "shelf" or r == "fence") then
        return "cliff"
      end
      return cls
    end

    local key = m * 2 + (blocked and 1 or 0)
    local hit = ctx.classCache[key]
    if hit ~= nil then return asLandscape(hit or nil, cx, cy) end

    local b = ctx.attributes(m)
    local class = behaviour[b]

    if class == nil then
      -- no stated opinion: structural
      class = blocked and "wall" or "ground"
    elseif class == "ground" or class == "grass" or class == "slope" then
      -- a stated GROUND-ish answer on a cell you cannot enter is a wall
      -- wearing ground art: the base course of a building, the foot of a
      -- cliff, the trunk row under a canopy.  Emerald draws a great many of
      -- those as MB_NORMAL, and taking the behaviour literally laid every
      -- building in Rustboro flat on the pavement.
      if blocked then class = "wall" end
    end


    -- A PASSABLE CELL CANNOT BE SOMETHING YOU ARE STANDING INSIDE.
    --
    -- The behaviour row is a statement about the art; the collision bit is a
    -- statement about where the player can be, and where they disagree the
    -- collision bit wins.  MB_MOUNTAIN_TOP is the crater rim in Sootopolis
    -- and a walkable rock shelf in Pacifidlog out of the same byte, so a
    -- profile that stands the rim up two courses would otherwise bury the
    -- player in every ledge of the raft town.
    --
    -- Doors are the exception and are named as such: a door cell is walkable
    -- -- you step onto it to warp -- and still has to rise with the wall it
    -- is cut into, or the facade ends up with a doorway-shaped hole in it.
    --
    -- A RAIL LOOKS LIKE THE SAME EXCEPTION AND IS NOT -- MEASURED AND REVERTED.
    --
    -- `MB_VERTICAL_RAIL` and its three siblings sit on walkable cells, so this
    -- rule turns them into ground and they draw as a painted stripe lying in
    -- the floor rather than a fence standing on it.  Letting them through --
    -- `and not railBehaviour[b]`, with the four rows set to "fence" in
    -- `gen3_shapes` -- does stand them up, and it does help the ledges:
    -- crossing ledges went 171 correct (48%) to 180 (51%) and flat 114 to 105.
    --
    -- It also broke the one invariant every revision of this work has held.
    -- A rail cell that is no longer `floor` leaves the walkable terrace
    -- components, and Sootopolis is laced with rails along every terrace edge:
    -- **impossible steps went from 1 in 166,642 to 5, and non-course heights
    -- from 37 to 112.**  A 32px step between two cells you can walk between is
    -- a wall you can walk through, and no amount of correctly-standing fence
    -- is worth one.
    --
    -- Standing a rail up needs a class that draws a bar on a cell that stays
    -- part of the floor -- the `standing` set is the wrong mechanism for it,
    -- because that set exists precisely to say "this only applies where the
    -- player cannot be".
    if not blocked and standing[class] and not doorBehaviour[b] then
      class = "ground"
    end

    -- COVER on a blocked cell is what stands up.  `wall` and `tree` are the
    -- same box to the mesher, so this is not about the height -- it is about
    -- the run machinery, which measures a tree from its trunk and a wall from
    -- its footing, and about profiles that want to say "this tileset\'s cover
    -- is forest" once instead of tile by tile.
    if blocked and class == "wall" and ctx.coverAt(m) then
      class = ctx.coverClass or "wall"
    end

    ctx.classCache[key] = class

    -- LANDSCAPE ROCK IS NOT A BUILT WALL, AND THE MESHER TREATS THEM
    -- DIFFERENTLY.
    --
    -- Every blocked MB_NORMAL cell lands on class `wall` above, and in
    -- Sootopolis that is the whole crater: the town's rock is MB_NORMAL from
    -- the shore to the rim.  `wall` hands the cell to the building-run
    -- machinery, which SKIPS it expecting a founded run to cover it -- and
    -- where no run comes, or one comes founded on the street below, the cell
    -- is drawn at nothing.  Measured: 108 cells in Sootopolis meshed below
    -- every neighbour, EVERY ONE of them class `wall`, and 73 of those skipped
    -- with nothing drawn at all.  In the frame they are square holes punched
    -- through a terrace, reported at the corners of the ash cliffs.
    --
    -- `roleAt` has already done the hard half of this: a blocked mass with a
    -- warp under it is a building and everything else blocked is landscape,
    -- whatever it is painted.  So the class follows the role -- if the role
    -- says cliff or shelf, the cell is rock and is meshed as rock.
    --
    -- Deliberately NOT cached: `class` here is a property of the metatile and
    -- the cache is keyed by it, while the role is a property of the CELL --
    -- the same white stone is a building wall where a door stands under it and
    -- a crater terrace twenty cells away.
    --
    -- In-game location: Sootopolis City, the corners of the ash-white terraces
    -- all over the town, and the crater rim along the top of the map.
    -- The guard matters: `roleAt` reaches back here -- roleAt ->
    -- isBuildingCell -> buildings -> roofAt -> sceneryAt -> the scenery carve,
    -- which asks classAt.  The inner call gets the uncorrected class, which is
    -- what the carve wants anyway: it asks what the metatile is painted as,
    -- not what the terrain pass decided.
    return asLandscape(class, cx, cy)
  end

  -- The per-tileset profile, resolved through data/gen3_maps.lua: the engine
  -- keys a Gen 3 pair by ROM ADDRESS (TILESET_0286798_02870BC), which is a
  -- fact about one cartridge and useless to author against.  The map id is
  -- MAP_G<group>_N<number>, which IS the cartridge\'s own stable identity, so
  -- the profile is looked up by map and names its tilesets in pokeemerald\'s
  -- vocabulary.
  local maps = nil
  do
    local okMaps, m = pcall(V.data, "gen3_maps")
    if okMaps and type(m) == "table" then maps = m end
  end
  local entry = maps and maps.maps and maps.maps[tostring(map.id)] or nil
  ctx.mapName = entry and entry.name or nil
  ctx.primaryName = entry and entry.primary or nil
  ctx.secondaryName = entry and entry.secondary or nil
  ctx.kind = entry and entry.kind or nil
  -- IS THIS MAP OUTDOORS? Emerald states it in the map's MAP_TYPE, which
  -- data/gen3_maps.lua carries -- and a great deal hangs on the answer: the
  -- pitched-roof rule, the object carver's background aprons, grass, flowers,
  -- the sky, and whether the elevation grid is a height field or sprite
  -- priority. A map the data file has never heard of (a mod's own map, a
  -- fan-hack layout) falls back to the engine's own reading rather than
  -- silently becoming an interior.
  if entry and entry.outdoor ~= nil then
    ctx.outdoor = entry.outdoor and true or false
  else
    local okM, MapMod = pcall(require, "src.world.Map")
    if okM and MapMod and type(MapMod.isOutdoor) == "function" then
      local okO, v = pcall(MapMod.isOutdoor, def)
      ctx.outdoor = (okO and v) and true or false
    else
      ctx.outdoor = false
    end
  end

  -- profile overlay: the secondary tileset is the specific one, so it wins
  -- over the primary, and a per-MAP entry wins over both.
  local profile = {}
  local function overlay(from)
    if type(from) ~= "table" then return end
    for k, v in pairs(from) do profile[k] = v end
  end
  if spec_ and spec_.tilesets then
    overlay(spec_.tilesets[ctx.primaryName])
    overlay(spec_.tilesets[ctx.secondaryName])
  end
  if spec_ and spec_.maps then overlay(spec_.maps[ctx.mapName]) end
  -- METATILE PINS, primary then secondary then the map: most general to most
  -- specific, each overlaying the last, the same order as the profile itself.
  local pins = nil
  local function addPins(from)
    if type(from) ~= "table" then return end
    pins = pins or {}
    for id, cls in pairs(from) do
      pins[tonumber(id) or -1] = (cls ~= false) and cls or nil
    end
  end
  if spec_ and spec_.metatiles then
    addPins(spec_.metatiles[ctx.primaryName])
    addPins(spec_.metatiles[ctx.secondaryName])
  end
  if spec_ and spec_.map_metatiles then
    addPins(spec_.map_metatiles[ctx.mapName])
  end
  ctx.pins = pins

  ctx.profile = profile
  -- heights asked BEFORE the profile resolved were answered without it --
  -- the levels scan itself asks a few -- and the cache would hold those
  -- unflagged answers forever.  Start clean now that the profile can speak.
  for k in pairs(groundCache) do groundCache[k] = nil end
  -- ...and CLASSES for exactly the same reason.  The deck rule above reads
  -- `profile.use_elevation`, so every class answered during setup was
  -- answered as if the profile said nothing -- and Victory Road's thirty
  -- crossings stayed cached as `ground` however right the rule was.
  for k in pairs(ctx.classCache) do ctx.classCache[k] = nil end
  ctx.coverClass = profile.cover
  ctx.bridgeLift = (spec_ and spec_.bridge_lift) or {}
  -- ...and the courses a span rides ABOVE that storey.  See the table's own
  -- note in data/gen3_shapes.lua: it is a stated number, not a measured one,
  -- and it is keyed on the one behaviour that names the cycling road.
  ctx.spanFreeboard = (spec_ and spec_.span_freeboard) or {}
  if type(profile.bridge_lift) == "table" then
    local merged = {}
    for b, v in pairs(ctx.bridgeLift) do merged[b] = v end
    for b, v in pairs(profile.bridge_lift) do merged[b] = v end
    ctx.bridgeLift = merged
  end
  -- A profile may restate any behaviour row for its own tileset -- Fortree's
  -- MB_NORMAL cover is canopy, Sootopolis' is masonry -- so merge rather than
  -- replace, and do it here, after the overlay, so the merged table is what
  -- classAt closes over.
  if type(profile.behaviour) == "table" then
    local merged = {}
    for b, c in pairs(behaviour) do merged[b] = c end
    for b, c in pairs(profile.behaviour) do
      merged[b] = (c ~= false) and c or nil
    end
    behaviour = merged
  end
  -- INDOORS, ELEVATION IS NOT HEIGHT.
  --
  -- Outdoors the field is a real Y axis -- terraces, bridges, the Sootopolis
  -- crater. Indoors Emerald uses it for SPRITE PRIORITY: which side of a bed
  -- or a counter the player draws on. Brendan's bedroom is a flat floor whose
  -- elevation grid reads
  --
  --     0 3 0 3        two cells at level 4, in a chequer around the bed
  --     4 0 4 0
  --     0 3 0 3
  --
  -- and ranking those into courses stood a 16px slab in the middle of the
  -- carpet -- the "weird repeating texture" in the room, which was a step
  -- nobody can see in the flat game because there is no step.
  --
  -- So an indoor map is flat unless its profile asks otherwise. `outdoor`
  -- comes from data/gen3_maps.lua, which reads it off the map's MAP_TYPE.
  --
  -- SO ASK THE MAP, rather than gate it by tileset.  Sprite priority is
  -- SCATTERED -- a chequer of single cells around a bed -- and a real
  -- terrace is a REGION.  Measured over all 518 maps, the two do not
  -- overlap and there is nothing in between: the largest connected
  -- non-datum walkable region is 1 cell in a Pokemon Center, 2 in Aqua
  -- Hideout B1F, 3 in Devon Corp 3F, 4 in the Fan Club... and then 12 in
  -- Aqua Hideout 1F, 20 in Mirage Tower 4F, 42-54 across the Battle Pyramid
  -- squares.  A threshold of 8 sits in that gap with room on both sides.
  --
  -- This is what "use the ROM's elevation on every map" means in practice:
  -- 24 indoor maps that were being flattened by a blanket rule now build
  -- their real floors, and the bedrooms that rule existed to protect are
  -- still protected -- by evidence from their own data rather than by a
  -- hand-written list.  A profile may still force it either way.
  local ELEV_REGION_MIN = 8
  local function elevationIsReal()
    if profile.use_elevation ~= nil then return profile.use_elevation == true end
    local W2 = tonumber(width) or 0
    local H2 = tonumber(height) or 0
    if W2 < 1 or H2 < 1 then return false end
    local seen = {}
    local function K(x, y) return y * 8192 + x end
    for cy = 0, H2 - 1 do
      for cx = 0, W2 - 1 do
        local e = ctx.elevationAt(cx, cy)
        if e and e ~= ELEV_TRANSITION and e ~= ELEV_SURF and e ~= ELEV_DEFAULT
           and e ~= ELEV_MULTI and not seen[K(cx, cy)] then
          seen[K(cx, cy)] = true
          local st, sz = { { cx, cy } }, 0
          while #st > 0 do
            local c = table.remove(st)
            sz = sz + 1
            if sz >= ELEV_REGION_MIN then return true end
            for _, d in ipairs(NEIGHBOURS) do
              local nx, ny = c[1] + d[1], c[2] + d[2]
              if nx >= 0 and ny >= 0 and nx < W2 and ny < H2
                 and not seen[K(nx, ny)]
                 and ctx.elevationAt(nx, ny) == e then
                seen[K(nx, ny)] = true
                st[#st + 1] = { nx, ny }
              end
            end
          end
        end
      end
    end
    return false
  end
  if entry and ctx.outdoor == false and not elevationIsReal() then
    elevHeight, levels = nil, 0
  end
  -- what the rest of the build should ask, instead of re-reading the flag
  ctx.usesElevation = (elevHeight ~= nil)

  if profile.course then
    -- a tileset whose terraces are drawn shallower or deeper than one cell
    local c = tonumber(profile.course)
    if c and c > 0 and elevHeight then
      for e, h in pairs(elevHeight) do
        if e ~= ELEV_SURF then elevHeight[e] = h / COURSE * c end
      end
    end
  end

  -- THE FLOOR OF THIS PARTICULAR ROOM.
  --
  -- Deriving the background from the tileset alone gets outdoors right and
  -- interiors wrong. Outdoors, Emerald paints grass under every roof, so the
  -- ground identifies itself. Indoors there is nothing drawn on top of the
  -- floor, and the fallback -- a floor is the art that TILES seamlessly --
  -- catches lino and carpet but misses any floor whose pattern repeats over
  -- TWO cells, which is most wooden flooring in the game: Brendan's house
  -- carved nothing at all, so every table, television and PC in it stayed a
  -- solid block. Across the game that left 94% of indoor blocked cells as
  -- generic wall.
  --
  -- The map knows. A metatile the map places on a WALKABLE cell is floor by
  -- definition -- you are standing on it. That is a per-map fact, so it keys
  -- a per-map variant of the shape surface rather than the pair's own.
  do
    local counts, total = {}, 0
    for cy = 0, height - 1 do
      for cx = 0, width - 1 do
        if not ctx.blockedAt(cx, cy) then
          local m = ctx.metatileAt(cx, cy)
          if m then counts[m] = (counts[m] or 0) + 1 total = total + 1 end
        end
      end
    end
    local list = {}
    for m, n in pairs(counts) do list[#list + 1] = { m, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    -- the floors people actually walk on, not every one-off doormat: keep
    -- the metatiles that cover the bulk of the walkable area
    local floor, acc = {}, 0
    for i = 1, #list do
      local m, n = list[i][1], list[i][2]
      if i <= 12 and (n >= 3 or acc < total * 0.6) then
        floor[#floor + 1] = m
        acc = acc + n
      end
    end
    table.sort(floor)
    ctx.floorMetatiles = floor
    ctx.floorKey = table.concat(floor, ",")
  end

  -- ==========================================================================
  -- WHAT EACH CELL IS, from the metatile role table.
  --
  -- data/gen3_metatiles.lua says what a metatile is DRAWN as; the blockdata
  -- says whether this particular cell is standable.  Neither answers alone.
  -- Route 111's plateau top and the wall under it are both metatile 113 --
  -- sixteen rows of rock either way -- and the only thing that separates them
  -- is that one cell is walkable and the other is not.
  --
  -- Owner keys come off the tileset key itself ("TILESET_03DF704_03DF77C"):
  -- ids under 512 belong to the primary, the rest to the secondary.
  -- ==========================================================================
  do
    local roles = nil
    do
      local okR, t = pcall(V.data, "gen3_metatiles")
      if okR and type(t) == "table" then roles = t.roles end
    end
    -- The tileset the map carries is the baked PAIR object, not its name --
    -- `map.tileset` is a table.  The pair's identity lives in three places
    -- and they do not always all exist: the def's key string, the pair's own
    -- `id`, and the two `primaryKey`/`secondaryKey` halves.  Read them in
    -- that order rather than assuming any one is present.
    local ts = map.tileset
    local key = (type(ts) == "table" and tostring(ts.id or ""))
                or (type(ts) == "string" and ts) or ""
    if key == "" and type(map.def) == "table" then
      key = tostring(map.def.tileset or "")
    end
    local p1, s1 = key:match("TILESET_(%x+)_(%x+)")
    if not p1 and type(ts) == "table" then
      p1 = tostring(ts.primaryKey or ""):match("TILESET_(%x+)")
      s1 = tostring(ts.secondaryKey or ""):match("TILESET_(%x+)")
    end
    if not p1 then p1 = key:match("TILESET_(%x+)") end
    ctx.ownerPrimary = p1 and ("P" .. p1) or nil
    ctx.ownerSecondary = s1 and ("S" .. s1) or nil

    local roleMemo = {}

    -- art, material, cap, face, kind, motif -- nil when the metatile is not
    -- one Hoenn ever places (a mod's own tileset, a slot the ROM leaves empty)
    function ctx.metaRole(m)
      if not roles or not m then return nil end
      local owner = (m < 512) and ctx.ownerPrimary or ctx.ownerSecondary
      local t = owner and roles[owner]
      local r = t and t[m]
      if not r then return nil end
      return r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
    end

    -- ------------------------------------------------------------------
    -- A TILESET THAT STATES NO VERTICAL STRUCTURE AT ALL.
    --
    -- MOTIVATED BY HOENN'S TWELVE DIVE MAPS -- Underwater_Route124 and its
    -- neighbours, and the submarine bay in Underwater_SeafloorCavern that
    -- the user photographed.
    --
    -- gTileset_Underwater is drawn TOP-DOWN.  All 150 of its rows are
    -- `cap 0, face 0`: no drawn top edge, and no drawn wall below one,
    -- because the cartridge never shows the SIDE of anything under water --
    -- it shades the sea floor from above and marks a change of level with a
    -- scalloped rim.  Every reader in this file that measures relief off
    -- `cap` and `face` -- `courseAt`, `faceKindAt`, `capGen3Rock` -- is
    -- therefore blind on it by construction, and reports a flat sea floor
    -- however the art is shaded.
    --
    -- It is the ONLY owner of the 72 in `data/gen3_metatiles.lua` of which
    -- that is true.  Measured over the whole table: S03DFB24 is 150 rows of
    -- cap 0 face 0; the next flattest, S03DFD54, still draws a cap on 40 of
    -- its 46 rows, and no other owner comes close.  So "this tileset states
    -- no vertical structure" is a whole-tileset reading of the art that
    -- picks out exactly one tileset in Hoenn and nothing else, and it says
    -- something true about it: relief drawn here cannot be counted, only
    -- assumed.
    local flatOwner = {}
    function ctx.ownerStatesNoRelief(owner)
      if not (roles and owner) then return false end
      local hit = flatOwner[owner]
      if hit ~= nil then return hit end
      local t = roles[owner]
      local flat = false
      if t then
        flat = true
        for _, r in pairs(t) do
          if (tonumber(r[3]) or 0) ~= 0 or (tonumber(r[4]) or 0) ~= 0 then
            flat = false
            break
          end
        end
      end
      flatOwner[owner] = flat
      return flat
    end

    -- THE RESOLVED ROLE OF ONE CELL.  This is the vocabulary every terrain
    -- pass should be asking for instead of inventing its own.
    --
    --   floor    you stand on it
    --   stair    you stand on it and it is drawn as treads
    --   water    surf
    --   ledge    a one-way hop
    --   cliff    blocked landscape that IS the edge between two floors, and
    --            whose height is therefore the drop, not its drawing
    --   wall     blocked worked structure standing ON a floor
    --   tree     foliage: a standee, never terrain
    --   fence    blocked landscape STANDING IN a floor rather than
    --            dividing two -- a pen wall, a guard rail, a kerb.
    --            Drawn and meshed exactly as a cliff is; it is only
    --            not a boundary, so no crossing is charged for it
    --   prop     everything else blocked and standing on a floor
    -- does any four-neighbour of this cell take the player's weight?
    function ctx.touchesWalkable(cx, cy)
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = cx + d[1], cy + d[2]
        if not ctx.offMap(nx, ny) and not ctx.blockedAt(nx, ny) then
          return true
        end
      end
      return false
    end

    -- The art test `buildScenery.leafAt` uses, as a pure function of the
    -- metatile so it can be asked from here without re-entering the carve
    -- (roleAt -> sceneryAt -> onLand -> roleAt would cache a half-built
    -- answer for good).
    local function leafyMeta(m)
      if m == nil then return false end
      if ctx.pins and ctx.pins[m] then return false end
      local an = Gen3.analyse(map.tileset)
      local st = an and an.stats and an.stats[m]
      if not (st and st.leafy and (st.solid or 0) > 0.5) then return false end
      local okM, _, mat = pcall(ctx.metaRole, m)
      return okM and mat == "green" or false
    end

    -- ------------------------------------------------------------------
    -- A FENCE IS A DRAWN FACE THE GROUND ON BOTH SIDES OF IT SHARES.
    --
    -- The `cliff` arm at the bottom of `roleAt` is a catch-all -- anything
    -- blocked, drawn with a face or in a hard material, that no warp claims
    -- -- and Hoenn stands a great deal ON its ground that this swept up as
    -- the edge BETWEEN two grounds: the Safari Zone's pen walls, Route 110's
    -- cycling-road guard rails, the kerb round a flowerbed, a rock chip on a
    -- sandbank.  Every one of them was `cliff`, and `cliff` is a BOUNDARY --
    -- `isBoundaryRole` walks it and the terrace raster charges a course for
    -- every wall a crossing passes through.
    --
    -- The Safari Zone's north-east pen is where it shows.  Its 401 `cliff`
    -- cells go with only 43 `shelf` -- a ratio of 0.11 against Jagged Pass's
    -- 1.17, Route 111's 2.4 and 1.2-4.4 everywhere else -- so almost none of
    -- that rock has a drawn TOP behind it.  The field climbed one course per
    -- wall crossed and reached 96px over 886 cells, and g3-settle-231, which
    -- capped the climb, had to book 226 of those walls as "a cliff separating
    -- nothing", which is exactly what a fence IS and what the vocabulary had
    -- no word for.
    --
    -- The map-level ratio cannot classify a cell.  Its per-cell form can, and
    -- it is four readings of one drawing:
    --
    --   1. THE CELL DRAWS NO TOP OF ITS OWN.  `cap == 0`.  A cell that turns
    --      over from surface to wall is the lip of a step and keeps it.
    --   2. THE SAME GROUND STANDS ON BOTH SIDES OF IT.  Walk out through the
    --      rock along each axis -- the same walk `capGen3Rock` makes, and to
    --      the same depth a wall is ever drawn -- and the first walkable cell
    --      each way must exist and be drawn in the same material.  A cliff
    --      has ground on ONE side and mass on the other, or two DIFFERENT
    --      grounds: Route 111's mesa is rock over sand.
    --   3. NOTHING AROUND IT DRAWS A TOP EITHER.  No lip (a metatile with
    --      both cap and face), no blocked rock surface, and no cell that is
    --      blocked with no walkable neighbour -- which is `roleAt`'s own
    --      definition of `shelf`, asked of the neighbourhood instead of the
    --      map.  This is the shelf-to-cliff ratio made local.
    --   4. THE CARTRIDGE SIGNS NO DROP WITHIN REACH.  A LEDGE is Emerald's
    --      own signed statement that this edge is a drop you may hop, and a
    --      STAIRCASE that it is one you may climb; where either is within
    --      three cells of the wall through the rock, the drop is real however
    --      the face is drawn.  Ledges are the currency `GEN3_RELIEF_GATE`
    --      already prices relief in.
    --   5. AND IT HAS NO BODY: no two-by-two square of landscape contains it.
    --      A wall is a line; a mass is an area.
    --
    -- What a fence then IS to the rest of the model is already written down:
    -- `GEN3_STANDS_ON_GROUND` lists `fence`, so it takes the floor beside it;
    -- `isBoundaryRole` does NOT, so no crossing charges a course for it; and
    -- `asLandscape` below keeps its drawn class `cliff`, so the mesher builds
    -- exactly the wall it built before.  It stands, it is rock, it casts its
    -- shadow -- it just does not lift the ground behind it.
    --
    -- In-game location: the Safari Zone's north-east and north pens, whose
    -- rock walls divide one flat field into forty; Route 110's cycling road,
    -- where the guard rail runs along the deck; and Route 130's crags, which
    -- this must NOT reach as anything but landscape (see `standGen3Runs`).
    -- ------------------------------------------------------------------
    local FENCE_DEEP = 3               -- the depth a wall is ever drawn
    local RING8 = { { 0, -1 }, { 0, 1 }, { 1, 0 }, { -1, 0 },
                    { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

    -- THE TREAD TEST, as a pure function of the metatile.
    --
    -- The `stair` arm below states this reading and the evidence for it at
    -- length; this is the same three lines written where the fence test can
    -- ask them, because that test has to know whether the cartridge has cut a
    -- staircase through a wall and cannot re-enter `roleAt` to find out.
    -- (Same reason `leafyMeta` above restates `buildScenery.leafAt`.)
    -- Banded art that fills its cell and paints at most the one row of shadow
    -- under its bottom tread: Route 114's rock, 659 and 712, is banded at
    -- face 16 and still rejects.
    local function treadMeta(m)
      if m == nil then return false end
      local okR, art_, _, _, face_ = pcall(ctx.metaRole, m)
      if not okR or art_ ~= "banded" then return false end
      if (tonumber(face_) or 0) > 1 then return false end
      local an = Gen3.analyse(map.tileset)
      local st = an and an.stats and an.stats[m]
      if st and (st.solid or 0) < 0.75 then return false end
      return true
    end

    -- Blocked, and drawn as LANDSCAPE rather than as foliage -- the mass a
    -- face could be the front of.  A hedge is a standee and must not thicken
    -- a wall into a body; the test is `roleAt`'s own tree arm.
    local function massAt(cx, cy)
      if ctx.offMap(cx, cy) or not ctx.blockedAt(cx, cy) then return false end
      local mm = ctx.metatileAt(cx, cy)
      if mm == nil then return true end
      local okR, _, mat2, _, _, kind2, motif2 = pcall(ctx.metaRole, mm)
      if not okR then return true end
      if kind2 == "tree" or (motif2 and mat2 == "green") or leafyMeta(mm) then
        return false
      end
      return true
    end

    -- The material of the first ground reached walking out through the rock,
    -- or nil where the rock never ends inside a wall's depth.
    local function groundAcross(cx, cy, dx, dy)
      for step = 1, FENCE_DEEP do
        local nx, ny = cx + dx * step, cy + dy * step
        if ctx.offMap(nx, ny) then return nil end
        if not ctx.blockedAt(nx, ny) then
          local okR, _, mat2 = pcall(ctx.metaRole, ctx.metatileAt(nx, ny))
          if not okR or mat2 == nil then return nil end
          return mat2
        end
        if not massAt(nx, ny) then return nil end
      end
      return nil
    end

    local function fenceAt(cx, cy, m)
      -- 1. it draws no top of its own.  (Read here rather than taken from
      -- `roleAt`, whose own unpacking discards `cap`.)
      local okC, _, _, cap = pcall(ctx.metaRole, m)
      if not okC or (tonumber(cap) or 0) ~= 0 then return false end
      -- 5. and it has no body
      for _, o in ipairs({ { 0, 0 }, { -1, 0 }, { 0, -1 }, { -1, -1 } }) do
        local ax, ay = cx + o[1], cy + o[2]
        if massAt(ax, ay) and massAt(ax + 1, ay)
           and massAt(ax, ay + 1) and massAt(ax + 1, ay + 1) then
          return false
        end
      end
      -- 3. nothing around it draws a top
      for _, d in ipairs(RING8) do
        local nx, ny = cx + d[1], cy + d[2]
        if not ctx.offMap(nx, ny) then
          local okR, a2, _, cap2, face2 = pcall(ctx.metaRole,
                                                ctx.metatileAt(nx, ny))
          if okR then
            cap2 = tonumber(cap2) or 0
            face2 = tonumber(face2) or 0
            if cap2 > 0 and face2 > 0 then return false end
            if ctx.blockedAt(nx, ny) then
              if a2 == "surface" or cap2 >= 12 then return false end
              if not ctx.touchesWalkable(nx, ny) then return false end
            end
          end
        end
      end
      -- 2. the same ground on both sides
      local ground = nil
      for _, ax in ipairs({ { 0, 1 }, { 1, 0 } }) do
        local a = groundAcross(cx, cy, ax[1], ax[2])
        local b = groundAcross(cx, cy, -ax[1], -ax[2])
        if a and b and a == b then ground = a; break end
      end
      if ground == nil then return false end
      -- 4. the cartridge signs no drop within reach
      local seen = { [cy * 8192 + cx] = 0 }
      local q, qh = { { cx, cy } }, 1
      while qh <= #q do
        local c = q[qh]; qh = qh + 1
        local d = seen[c[2] * 8192 + c[1]] or 0
        local okR, _, _, _, _, kind2 = pcall(ctx.metaRole,
                                             ctx.metatileAt(c[1], c[2]))
        if okR and kind2 == "ledge" then return false end
        for _, dd in ipairs(NEIGHBOURS) do
          local nx, ny = c[1] + dd[1], c[2] + dd[2]
          if not ctx.offMap(nx, ny) then
            if not ctx.blockedAt(nx, ny) then
              if treadMeta(ctx.metatileAt(nx, ny)) then return false end
            elseif d < FENCE_DEEP and seen[ny * 8192 + nx] == nil
                   and massAt(nx, ny) then
              seen[ny * 8192 + nx] = d + 1
              q[#q + 1] = { nx, ny }
            end
          end
        end
      end
      return true
    end

    function ctx.roleAt(cx, cy)
      local k = cy * 8192 + cx
      local hit = roleMemo[k]
      if hit ~= nil then return hit end
      local m = ctx.metatileAt(cx, cy)
      local art, material, _, _, kind, motif = ctx.metaRole(m)
      local role
      if not art then
        role = ctx.blockedAt(cx, cy) and "prop" or "floor"
      elseif (kind == "water" or (material == "water" and ctx.blockedAt(cx, cy)))
             and behaviourNames[ctx.attributes(m)] == "water" then
        -- THE ART SAYS BLUE; THE CARTRIDGE SAYS WHAT IT IS.
        --
        -- `kind` and `material` are read off the DRAWING, and three buildings
        -- in Sootopolis are painted blue: the Pokemon Mart's roof, the Gym,
        -- and part of the Pokemon Center.  Twenty-four metatiles of worked
        -- structure were coming back `water`, which put water-surface geometry
        -- on their roofs -- "some of the water is raised when it shouldn't be"
        -- -- and, until the datum was moved to the behaviour byte, seeded the
        -- height flood at zero INSIDE the Mart, dragging the middle of the
        -- town down.  Traced: the cheapest path to (12,33), three terraces up
        -- in the art, began at (16,29) in the shop.
        --
        -- Every one of those cells is behaviour 0x00 MB_NORMAL or 0x69; the
        -- lake is 0x10 MB_POND_WATER and 0x14 MB_SOOTOPOLIS_DEEP_WATER.  The
        -- audit runs both ways and the other direction is empty: there is no
        -- cell in the region the ROM calls water that this reader missed.  So
        -- the art may propose water and the cartridge disposes.
        --
        -- In-game location: Sootopolis City -- the Mart (16,26)-(19,29), the
        -- Gym's frontage, and the Pokemon Center's blue trim.
        role = "water"
      elseif kind == "ledge" then
        role = "ledge"
      elseif not ctx.blockedAt(cx, cy) then
        -- A STAIRCASE IS BANDED ART THAT FILLS ITS CELL AND DRAWS NO FACE.
        --
        -- `banded` alone means "horizontal stripes", and Hoenn stripes a great
        -- deal that is not a flight: Slateport's promenade decking (528 x55,
        -- 530 x46), Pacifidlog's plank walkways (545 x25 and friends), and
        -- Route 114's rock faces.  Read as stairs they fed the height model
        -- flights that do not exist -- 137 stair cells on flat Slateport, 94
        -- on Route 114, 75 in a floating raft town -- and every one of them is
        -- a constraint saying two terraces differ when they do not.
        --
        -- The three separate cleanly and on the same two numbers:
        --
        --   Sootopolis 580/581   cap 16  face 0   solid 1.00   a flight
        --   Slateport  528/530   cap 16  face 0   solid 0.00   decking
        --   Pacifidlog 545/536   cap 16  face 0   solid 0.12   planks
        --   Route 114  659/712   cap 0   face 16  solid 0.62   rock
        --
        -- A flight is drawn as a solid block of treads and paints no vertical
        -- face; decking and planking are drawn as lines on open ground, and a
        -- rock face is mostly face.  So: banded, no face, and it fills its
        -- cell.
        local stair = (art == "banded")
        if stair then
          local an = Gen3.analyse(map.tileset)
          local st = an and an.stats and an.stats[m]
          -- the extra parentheses matter: `select` returns MANY values and
          -- tonumber would read the second as a numeric BASE
          --
          -- ...AND ONE ROW OF FACE IS THE SHADOW UNDER THE BOTTOM TREAD.
          --
          -- `face` is a count of ROWS, and "no face" was written `face_ > 0`.
          -- That threw away the General tileset's own staircase.  175 and 207
          -- are the grey stone steps Hoenn draws on every route -- Route 111,
          -- 112, 114, 115, 119, 120, 121, Mt Pyre's exterior, Lilycove,
          -- Mossdeep, Slateport, Ever Grande, the Safari Zone -- and the
          -- generated role table reads them
          --
          --   [175] = banded  manmade  cap 0  face 1  axis "y"
          --   [207] = banded  manmade  cap 0  face 1  axis "y"
          --
          -- one row of face, which is the shadow line under the bottom step.
          -- Route 112 shows the cost: its one staircase, (20..21, 41..43),
          -- climbing north off the grass onto the ash plateau, came back
          -- `floor` on all six cells and the map reported ZERO flights.
          --
          -- Read across the region, the readings among banded art that fills
          -- its cell are bimodal and this is not a close call:
          --
          --   face  0    758 cells      face  8      6 cells
          --   face  1    834 cells      face 10-15   32 cells
          --   face  2-7  310 cells      face 16    627 cells   <- rock faces
          --
          -- The rejection this test exists for is Route 114's rock, 659/712,
          -- which reads face 16 -- the whole cell IS the front face.  It still
          -- rejects.  A flight may draw one row of shadow; it may not be made
          -- of face.
          local face_ = tonumber((select(4, ctx.metaRole(m)))) or 0
          if face_ > 1 then stair = false end
          if st and (st.solid or 0) < 0.75 then stair = false end
          -- ...AND A ROOM IS NOT A FLIGHT.  See `floorPlateFor` above: the
          -- run this cell belongs to is too wide to walk up and is not cut
          -- into anything, which is a floor wearing plank art.  Littleroot's
          -- starter houses and Fortree's tree huts are the whole population.
          if stair then
            local plate = floorPlateFor(map, ctx)
            if plate and plate[cy * 8192 + cx] then stair = false end
          end
        end
        role = stair and "stair" or "floor"
      elseif kind == "tree" or (motif and material == "green")
             or leafyMeta(m) then
        -- ...AND THE SHAPE PASS AND THE ROLE PASS MUST READ ONE DRAWING.
        --
        -- `motif` is the generated table's word for "nothing with a face is
        -- ever drawn beneath this cell", which is true of a crown and false of
        -- the two cells UNDER it.  Hoenn's standard tree is four quarters --
        -- the General tileset's 198/199 over 22/23 -- and the lower pair carry
        -- the trunk's dark arc, so the table reads them `brow green cap 10
        -- face 1 motif=false` and this chain fell through to `cliff` (or, with
        -- no walkable neighbour, `shelf`).
        --
        -- `buildScenery`'s own `leafAt` has always read the same two cells
        -- correctly -- leafy texture, drawn green, solid over a half -- and
        -- gives them `cylinder`, so the MESHER draws a tree crown on a cell
        -- the TERRAIN model calls a cliff face.  That disagreement is not
        -- cosmetic: `isBoundaryRole` is cliff/shelf/wall and says in its own
        -- comment that "trees and props are excluded -- they STAND ON a
        -- terrace rather than divide it", and `Gen3.courseAt` scores a `brow`
        -- one course.  So every stand of trees drawn with 22/23 was a terrace
        -- boundary worth a 16px step, joining the ground on one side of a
        -- hedge to the ground on the other as though a wall stood between
        -- them.
        --
        -- Measured across all 518 maps: 2,693 cells on 40 maps, 2,671 of them
        -- already meshed as a crown.
        --
        --     Route113 425   Route120 254   Route119 251   Route112 228
        --     RusturfTunnel 212   Route123 198   Route114 126   Route111 117
        --
        -- The 22 that are not already crowns are 18 green cells standing
        -- against a house (Slateport 585, Lavaridge 536/529, Rustboro 775/500)
        -- and four Lavaridge ledge cells the `kind == "ledge"` branch above
        -- already claims.
        --
        -- In-game location: the tree lines along Routes 113, 119, 120 and 123
        -- and the mouth of Rusturf Tunnel -- anywhere Hoenn draws a two-cell
        -- tree rather than a four-quarter crown.
        role = "tree"
      elseif motif and ctx.attributes(m) ~= MB_MOUNTAIN_TOP then
        -- ...AND A MOUNTAIN TOP IS NOT A STANDALONE OBJECT.
        --
        -- `motif` means "nothing with a face is ever drawn beneath this cell",
        -- which the generator reads as foliage or an object standing on its
        -- own.  It is true of a MASS as well: a rock top that tiles over
        -- hundreds of cells has nothing but more rock top under it, so Route
        -- 114's 843 cells of gTileset_Fallarbor 577 -- 26% of the map -- came
        -- back `prop`, along with 572, 571, 569 and 595 and Route 115's 363.
        -- 1,287 blocked MB_MOUNTAIN_TOP cells region-wide.
        --
        -- A prop is not landscape to any pass downstream: it is outside
        -- `isBoundaryRole`, so a rock band that divides two terraces divides
        -- nothing; `asLandscape` leaves its class as built `wall` instead of
        -- rock; and `standGen3Runs` moves it whole as an object rather than
        -- founding it on the ground and raising its top.
        --
        -- Falling through instead, the two branches below give the answer the
        -- art already states -- a blocked `surface` cell with no walkable
        -- neighbour is a `shelf`, "ground you cannot walk on" -- which is what
        -- every neighbouring rock cell on those maps already comes back as.
        --
        -- In-game location: Route 114's rock flanks and Route 115's ridges,
        -- the two maps in Hoenn that draw a mountain top as a tiling surface.
        role = "prop"
      elseif ctx.isBuildingCell(cx, cy) then
        -- A WALL IS A WALL BECAUSE THERE IS A DOOR IN IT.
        --
        -- Material was the first answer here and it is wrong in both
        -- directions.  Sootopolis' crater terraces are worked white stone, so
        -- material called 1375 cells of landscape "wall" and the town came
        -- out flat -- no cliff anywhere to climb.  Petalburg's houses are
        -- drawn in the General tileset's warm reds, so material called them
        -- rock.  The cartridge settles it: the blocked mass a warp stands
        -- under is built, everything else blocked is landscape, whatever it
        -- is painted.
        role = "wall"
      elseif not ctx.touchesWalkable(cx, cy) then
        -- INSIDE A BLOCKED MASS, NOTHING IS A FACE.
        --
        -- Art cannot settle this in Sootopolis: the town is built of one
        -- white stone and a flat top of it reads `brow/manmade cap=1 face=1`
        -- -- one row of stone over one row of mortar -- exactly like the wall
        -- beside it.  365 cells of terrace top were classified as cliff on a
        -- one-pixel distinction that does not exist.
        --
        -- The neighbourhood settles it and needs no palette.  A cliff FACE is
        -- what you see from the ground in front of it, so it has walkable
        -- ground on at least one side.  A cell with none is buried in the
        -- middle of a raised mass: it is a top you cannot stand on.
        --
        -- The difference matters because a cliff is a BOUNDARY -- no terrace
        -- height of its own, excluded from the absorb, and sizeable by
        -- `capGen3Rock` only from walkable neighbours it does not have.  So
        -- an interior cell kept whatever height its drawing carried, and the
        -- middle of every stone block in the town sat at the wrong level.
        role = "shelf"
      elseif art == "surface" then
        -- A BLOCKED TOP IS NOT A WALL.
        --
        -- Sootopolis is mostly raised masonry with narrow streets cut through
        -- it, and the masonry is blocked -- you look at the top of a tier you
        -- cannot stand on.  Sweeping every blocked non-building cell into
        -- "cliff" made 80% of the town a vertical face, and a cliff is a
        -- BOUNDARY: it gets no terrace height of its own, it is excluded from
        -- the absorb, and `capGen3Rock` can only size it from walkable
        -- neighbours it does not have.  So the middle of every stone block
        -- kept whatever height its drawing happened to carry, which is the
        -- sunken ground in the report.
        --
        -- The art already distinguishes them and this branch was ignoring it:
        -- "surface" is sixteen rows of top, "face" and "brow" are the ones
        -- with a wall in them.  A shelf is ground you cannot walk on -- it
        -- takes a terrace height like any other ground and never acts as a
        -- boundary between two.
        role = "shelf"
      elseif art == "face" or art == "brow" or material == "rock"
             or material == "sand" or material == "stone"
             or material == "manmade" then
        role = fenceAt(cx, cy, m) and "fence" or "cliff"
      else
        role = "prop"
      end
      roleMemo[k] = role
      return role
    end
  end

  -- ==========================================================================
  -- BUILDINGS ARE THE RUNS ABOVE THE DOORS.
  --
  -- Every previous answer to "is this blocked cell a house" came from the art
  -- -- roof rows, siding colour, window bands -- and every one was wrong
  -- somewhere, because Emerald builds a crater terrace and a house wall out of
  -- the same worked stone.  Sootopolis came back with 264 building runs; the
  -- town has thirteen doors.
  --
  -- A door is a WARP and warps are map data.  Walk the blocked run directly
  -- north of each warp, then take the neighbouring columns while they carry a
  -- run whose top is within a row of the same roofline.  That is the house, it
  -- stops at the street, and it needs no palette and no map name.  Everything
  -- blocked that no warp reaches is landscape.
  --
  -- The vertical reach is capped at eight cells: Emerald's tallest outdoor
  -- facade is the Lilycove department store, and an uncapped walk climbs a
  -- house into the cliff behind it.
  -- ==========================================================================
  do
    local built = nil
    local function blockedCell(cx, cy)
      if cx < 0 or cy < 0 or cx >= width or cy >= height then return false end
      return ctx.blockedAt(cx, cy)
    end
    -- IS THIS CELL DRAWN AS FOLIAGE AND NOTHING ELSE?
    --
    -- `roleAt`'s `leafyMeta` exactly -- leafy texture, drawn green, solid
    -- over a half -- written here as a pure function of the metatile so the
    -- column walk can ask it without re-entering roleAt (roleAt ->
    -- isBuildingCell -> buildings is this very function).  The three parts
    -- matter and `leafy` alone will not do: Fortree's hut wall, 556 and 558,
    -- has the canopy draped over it and reads leafy, but the generated table
    -- calls it `brow / ROCK / cap 8 / face 8` -- logs, with leaves on them.
    -- Its corner pieces 555/559/563/567 and the forest around them are
    -- `surface / GREEN / cap 16 / face 0`, the same reading as the General
    -- tileset's own tree.  Material is what separates the wall from the wood,
    -- and it is the separation `roleAt` already makes: (9,2) comes back
    -- `wall` and (8,2) beside it comes back `tree`.
    local function foliageCell(cx, cy)
      local mm = ctx.metatileAt(cx, cy)
      if mm == nil then return false end
      local an = Gen3.analyse(map.tileset)
      local st = an and an.stats and an.stats[mm]
      if not (st and st.leafy and (st.solid or 0) > 0.5) then return false end
      local okM, _, mat = pcall(ctx.metaRole, mm)
      return (okM and mat == "green") == true
    end
    -- How rare a metatile has to be to count as a building's own art rather
    -- than the landscape it backs onto.  Four leaves room for a motif a
    -- building repeats across its own frontage and is far below the tens and
    -- hundreds that landscape tiles at.
    --
    -- Declared HERE rather than under `ctx.metatileCounts`, where it used to
    -- sit, because `runAbove` needs it now.  Nothing else about it changed.
    local RARE_BUILD = 4

    -- A DOORWAY YOU WALK INTO IS STILL A DOORWAY IN A BUILDING.
    --
    -- MOTIVATED BY THE SEASIDE CYCLING ROAD'S GATE HOUSES: ROUTE 110
    -- (14..19, 12..16) and (15..20, 84..88), ROUTE 111 (12..17, 109..113).
    -- Reported as "in route 110 the cycling road building needs to be fixed".
    --
    -- `runAbove` is where a building BEGINS.  Everything downstream is
    -- measured off what it returns -- the footprint, `bldRows`,
    -- `bldRoofRows`, the founded facade, the roofline levelling and the late
    -- "a building's box covers its whole footprint" restore.  Its first line
    -- refused outright when the cell above the warp was not blocked, and
    -- Emerald draws these gate houses with a WALK-BEHIND LINTEL: metatile
    -- 641, the arched recess over each of the two doors, is drawn on the
    -- ABOVE-PLAYER layer and left WALKABLE so the player can step into the
    -- doorway before the warp fires.  So `runAbove` answered nil,
    -- `ctx.buildings` claimed nothing at all, and a five-by-five gate house
    -- fell through to the generated role table, which reads its metatiles as
    -- `cliff`.  `capGen3Rock` then gave each of its columns "the drop it
    -- separates" and they came out at 16, 32, 48 and 64 side by side -- the
    -- jumble of grey and yellow boxes at four different heights in the
    -- report, with the wall's own door and window art lying flat on their
    -- tops because a `cliff` column's lid wears the cell's tile.
    --
    -- The walk-behind row is exactly the thing this function already grows a
    -- footprint UP through, four rows at a time ("A BUILDING YOU WALK BEHIND
    -- IS STILL THE BUILDING" -- the Mirage Tower, sixty lines below).  The
    -- same three-part test is asked of the row the door opens THROUGH, so the
    -- walk may start on one as well as finish on one.
    --
    -- ...AND THE RECESS IS A HOLE IN A WALL OVER A DOOR, WHICH IS A BETTER
    -- READING THAN "DRAWN ABOVE THE PLAYER" AND SUBSUMES IT.
    --
    -- g3-causeway-273 admitted the gate houses by asking whether the skipped
    -- row was drawn OVERHEAD, solid and bespoke.  That is true of the gate
    -- houses' arch (metatile 641, above-player) and FALSE of STERN'S
    -- SHIPYARD, SlateportCity (24..31, 32..38), reported as "sterns shipyard
    -- in slateport needs to be fixed".  Emerald draws the shipyard's entrance
    -- as a recess cut TWO cells into the south wall -- (26,38) is the warp
    -- and (26,37) the porch behind it -- and both on the BOTTOM layer,
    -- because you stand IN the doorway and must be drawn in front of it.  So
    -- `runAbove` answered nil, `ctx.buildings` claimed nothing, and 47 cells
    -- of shipyard fell to the generated role table as `cliff`/`shelf`.
    -- `capGen3Rock` then gave each column "the drop it separates" -- 0, 14,
    -- 16, 30, 32, 48 and 80 side by side -- which is the heap of grey slabs
    -- with the corrugated roof art lying on their tops in the report.  The
    -- same picture as the gate houses, reached through the same nil by a
    -- different route.
    --
    -- What is true of both, and of nothing else, is the SHAPE: a doorway is A
    -- HOLE IN A WALL, over a DOOR.  Three things, none of them a reading of
    -- which layer the art is on:
    --   * blocked mass to the east AND the west in the cell's own row, and
    --     blocked mass above the skipped run -- a hole in a wall;
    --   * the column carries a WARP on the door row -- the recess is cut over
    --     a door, and `ctx.warpCells` is already the map's own answer to that;
    --   * the art is SOLID and bespoke, the two tests this function already
    --     uses everywhere else for "the building's own art, filling its cell".
    --
    -- MEASURED over all 518 maps and all 1,312 warps.  756 warps have an
    -- unblocked cell above them.  Twenty of those cells are a hole in a wall
    -- with mass above; TEN are indoors, where this function answers about
    -- rooms rather than about a building seen from outside and where two more
    -- rules in it are already outdoors-only.  The remaining EIGHT split on
    -- SOLIDITY with nothing between them:
    --
    --   solid 1.00   Route110 (15,16) (18,16) (16,88) (19,88)   gate houses
    --   solid 1.00   Route111 (13,113)                          gate house
    --   solid 1.00   SlateportCity (26,38)                      the shipyard
    --   solid 0.23   JaggedPass (16,18)                         a CAVE MOUTH
    --   solid 0.23   Route112 (11,36)                           Fiery Path
    --
    -- Six at 1.00 against two at 0.23, a gap of two thirds of the statistic's
    -- range, and the two below it are the exact case the cave-mouth rule at
    -- the end of this function exists to throw away: a dark arch is mostly
    -- NOT INK, and a door in a wall is a solid piece of that wall with a
    -- doorway drawn on it.  `solid >= 0.9` is this file's own constant for
    -- "fills its cell" and nothing here is tuned: anything from 0.3 to 1.0
    -- cuts the same six.
    --
    -- THE WARP CLAUSE IS WHAT KEEPS IT OFF THE FLANKS.  `runAbove` is asked
    -- of every column the walk and the bespoke-art widening try, not only of
    -- the door's, so without it Route 113's Glass Workshop grew a third
    -- column through two WALKABLE cells at (34,2) and (34,4) -- a hole in a
    -- wall that is not a doorway, and a floor the building's box would then
    -- have stood 32px of wall on.  A recess is cut over a door; this asks
    -- whether there is one.
    --
    -- Bounded to TWO rows, the deepest recess Emerald draws over a door: the
    -- shipyard's porch is two, the gate houses' arch is one.
    local LINTEL_MAX = 2
    local function lintelCell(cx, cy)
      local mm = ctx.metatileAt(cx, cy)
      if mm == nil then return false end
      if not ctx.outdoor then return false end
      -- a hole in a wall has wall on both sides of it, in its own row
      if not (blockedCell(cx - 1, cy) and blockedCell(cx + 1, cy)) then
        return false
      end
      local an = Gen3.analyse(map.tileset)
      local st = an and an.stats and an.stats[mm]
      if not (st and (st.solid or 0) >= 0.9) then return false end
      local counts = ctx.metatileCounts()
      return (counts[mm] or 0) <= RARE_BUILD
    end
    local function runAbove(cx, doorY)
      local y = doorY - 1
      if y < 0 then return nil end
      local mass = y
      if not blockedCell(cx, mass) then
        -- ...and only over a door of this column's own (see above)
        local ws = ctx.warpCells()
        if not (ws and ws[doorY * 8192 + cx]) then return nil end
        local n = 0
        while n < LINTEL_MAX and mass - n >= 0
              and not blockedCell(cx, mass - n)
              and lintelCell(cx, mass - n) do
          n = n + 1
        end
        if n == 0 then return nil end
        mass = mass - n
        if mass < 0 or not blockedCell(cx, mass) then return nil end
      end
      local top = mass
      while top - 1 >= 0 and blockedCell(cx, top - 1) and (y - (top - 1)) < 8 do
        top = top - 1
      end
      return top, y
    end
    -- HOW MANY TIMES EACH METATILE IS LAID ON THIS MAP.  One scan, memoised:
    -- the roof-apex rule below and anything else that needs to tell bespoke
    -- art from tiling landscape asks this rather than scanning again.
    local metaCounts = nil
    function ctx.metatileCounts()
      if metaCounts then return metaCounts end
      metaCounts = {}
      for cy = 0, height - 1 do
        for cx = 0, width - 1 do
          local m = ctx.metatileAt(cx, cy)
          if m then metaCounts[m] = (metaCounts[m] or 0) + 1 end
        end
      end
      return metaCounts
    end

    -- (`RARE_BUILD` used to be declared here.  It moved above `runAbove`,
    -- which now needs it -- see A DOORWAY YOU WALK INTO IS STILL A DOORWAY
    -- IN A BUILDING.  Same value, same readers.)

  -- WHERE THE CARTRIDGE PUTS A DOOR.
  --
  -- Every warp on the map as a cell set, with no judgement about what it
  -- opens into.  `ctx.buildings` decides which warps are shops and which are
  -- holes in a cliff; the height passes need to know only that a doorway is
  -- there, because a doorway is a hole in a wall and not ground the wall
  -- banks down to.
  local warpSet = nil
  function ctx.warpCells()
    if warpSet then return warpSet end
    warpSet = {}
    local ws = nil
    do
      local okE, ed = pcall(engineData)
      local all = okE and ed and ed.maps or nil
      local rec = all and (all[tostring(map.id)] or all[map.id]) or nil
      ws = rec and rec.warps or nil
      if not ws and type(map.def) == "table" then ws = map.def.warps end
    end
    if type(ws) == "table" then
      for _, wp in ipairs(ws) do
        local wx, wy = tonumber(wp.x), tonumber(wp.y)
        if wx and wy then warpSet[wy * 8192 + wx] = true end
      end
    end
    return warpSet
  end

  function ctx.buildings()
      if built then return built end
      built = { list = {}, cell = {} }
      local warps = nil
      do
        local okE, ed = pcall(engineData)
        local all = okE and ed and ed.maps or nil
        local rec = all and (all[tostring(map.id)] or all[map.id]) or nil
        warps = rec and rec.warps or nil
        if not warps and type(map.def) == "table" then warps = map.def.warps end
      end
      if type(warps) ~= "table" then return built end
      -- WHERE THE ROOF IS, THE BUILDING IS.
      --
      -- `runAbove` walks blocked cells, and outdoors that walk does not stop
      -- where the building does.  Sootopolis' Pokemon Center has a bench and
      -- a stone brow drawn behind it, so its columns run five cells deep, and
      -- matching neighbours on the END of that run took the plaza column east
      -- of the shop (46) while rejecting the shop's own west column (42).
      -- Half the Center meshed as grey pavement standing on end.
      --
      -- A roof is the one thing Emerald states plainly (`roofAt`: the top
      -- half drawn above the player, filling the cell), so where the door
      -- column has one, the facade starts at it and a neighbour joins only
      -- if its own roof starts within a row.  Where no roof is stated -- the
      -- Mart, whose blues the analyser reads as lake -- nothing changes and
      -- the old end-matching rule stands.
      -- ...AND A FLANK COLUMN'S ROOFLINE IS LOOKED FOR AT THE DOOR'S, NOT
      -- WHEREVER ITS OWN MASS HAPPENS TO REACH.
      --
      -- MOTIVATED BY ROUTE 110'S NORTHERN CYCLING ROAD GATE HOUSE,
      -- (14..19, 12..16).
      --
      -- `roofTop` returns the TOPMOST roof row of the column's blocked run,
      -- and `runAbove` walks up to eight rows -- so a column of a building
      -- that happens to back onto more blocked landscape answers with the
      -- LANDSCAPE's roofline.  The gate house's east column, x=18, is five
      -- rows of building standing under six rows of the coastal sea wall
      -- with no gap between them: its run is rows 8..15 and (18,8) is drawn
      -- overhead and solid, so `roofTop` came back 8 against the door
      -- column's 13 and the column was refused.  x=19 is the same.  Two of
      -- the six columns of a gate house were thrown away, and the second
      -- door then founded a one-column building up the sea wall.
      --
      -- Where the door column has already stated a roofline there is nothing
      -- to discover above it: one building has one eave, which is the
      -- sentence this whole function is built on.  So a flank column is asked
      -- for its roof AT the door's roofline rather than at the top of its own
      -- mass, and the band it may answer in is the same one course either way
      -- the acceptance test always allowed.  This can only ever admit a
      -- column the old reading refused, and never a row above the door's own
      -- roofline -- so a shop still cannot eat the cliff behind it.
      local function roofTop(cx, doorY, floorY)
        local t, b = runAbove(cx, doorY)
        if not t then return nil end
        if floorY and floorY > t then t = floorY end
        for y = t, b do
          local okR, r = pcall(ctx.roofAt, cx, y)
          if okR and r then return y, b end
        end
        return nil
      end
      for _, wp in ipairs(warps) do
        local wx, wy = tonumber(wp.x), tonumber(wp.y)
        if wx and wy then
          local t0r = roofTop(wx, wy)
          local t0 = t0r or runAbove(wx, wy)
          -- ...AND A DOOR ALREADY INSIDE A BUILDING IS THAT BUILDING'S
          -- SECOND DOOR.
          --
          -- MOTIVATED BY THE CYCLING ROAD GATE HOUSES, which are the only
          -- structures in Hoenn Emerald gives TWO front doors -- Route 110
          -- (15,16)+(18,16) and (16,88)+(19,88).  The guard beside this one
          -- asks whether the TOP of the column is claimed, which is a
          -- question about one column's mass; the second door is three cells
          -- along, so it walked its own column and founded a second
          -- "building" out of the sea wall standing behind the gate house.
          -- A warp whose own cell the previous walk already claimed is a door
          -- into a building that exists.
          local twin = built.cell[wy * 8192 + wx] ~= nil
          if t0 and not twin and not built.cell[t0 * 8192 + wx] then
            local cells = {}
            local overheadRows = 0
            local taken = {}
            local function take(cx)
              local t, b = runAbove(cx, wy)
              if not t then return false end
              local rawTop = t
              if t0r then
                local r = roofTop(cx, wy, t0r - 1)
                if not r or math.abs(r - t0r) > 1 then return false end
                t = r
              elseif math.abs(t - t0) > 1 then
                return false
              end
              -- A BUILDING STOPS WHERE ITS OWN ART STOPS.
              --
              -- `runAbove` walks the blocked mass above the door and does not
              -- stop where the building does: Sootopolis' Pokemon Mart has the
              -- crater's stone drawn hard against its back, so the walk ran
              -- from the shopfront at y=29 up to y=23 and the footprint came
              -- out seven rows for a four-row shop.  Three rows of cliff were
              -- then given the shop's box and its roof -- and no Mart art to
              -- put on them, so the back of the roof wore pale terrace stone.
              -- That is the roof texture not reaching the full length of the
              -- roof.
              --
              -- `roofTop` is the cut where Emerald states a roof, and it is
              -- the better answer; this is the same cut for a building whose
              -- roof is drawn on the bottom layer and which therefore states
              -- none.  A building's art is BESPOKE -- the Mart's metatiles
              -- appear once or twice on the whole map -- and the landscape it
              -- backs onto TILES: 737 appears 299 times, 723 eighty-three,
              -- 738 seventy-three.  So walk down from the top of the run while
              -- the art is common, and start the building where it stops
              -- being.
              if not t0r then
                local counts = ctx.metatileCounts()
                while t < b do
                  local mm = ctx.metatileAt(cx, t)
                  if mm and (counts[mm] or 0) > RARE_BUILD then t = t + 1
                  else break end
                end
              end
              -- ...AND A BUILDING YOU WALK BEHIND IS STILL THE BUILDING.
              --
              -- `runAbove` walks BLOCKED cells, and Emerald draws the top of
              -- a tall structure on the above-player layer so you can pass
              -- behind it -- the same trick it uses for Rustboro's lamp heads
              -- and for a tree's crown.  Those cells are walkable, so the
              -- walk stops under them.
              --
              -- The Mirage Tower is the case.  Route 111, (18..20, 55..58):
              -- four cell rows of bespoke art, every metatile used exactly
              -- ONCE on the map, and only row 57 is blocked --
              --
              --   (19,55) 1001  walk  overhead  solid 1.00
              --   (19,56) 1009  walk  overhead  solid 1.00
              --   (19,57)  988  BLOCKED         solid 1.00
              --
              -- -- so the tower was founded two rows tall and rendered as a
              -- box on the sand instead of a tower.
              --
              -- A cell drawn OVERHEAD that fills its cell, directly above the
              -- mass, is part of it.  Bounded to four rows, which is taller
              -- than anything Hoenn draws this way, and it stops at the first
              -- cell that is not.
              -- counted as a MAX over the columns, not a sum: the walk runs
              -- once per column of the footprint and every column of the
              -- Mirage Tower grows the same four rows.  Summing them made a
              -- three-column tower report twelve rows of overhead and a
              -- Lavaridge house report seven for a four-row building.
              local grew = 0
              do
                local an = Gen3.analyse(map.tileset)
                for _ = 1, 4 do
                  local ny = t - 1
                  if ny < 0 then break end
                  local okB, bl = pcall(ctx.blockedAt, cx, ny)
                  if okB and bl then break end
                  local mm = ctx.metatileAt(cx, ny)
                  local st = mm and an and an.stats and an.stats[mm]
                  -- ...AND THE ART HAS TO BE THE BUILDING'S OWN.
                  --
                  -- Overhead and solid is also true of the desert's own sand
                  -- two rows above the tower, so the walk ran to row 53 for a
                  -- drawing that starts at 55.  The same test this function
                  -- already uses to find where a building's art stops applies
                  -- to where it starts: "a building's art is BESPOKE -- the
                  -- Mart's metatiles appear once or twice on the whole map --
                  -- and the landscape it backs onto TILES".  Every one of the
                  -- Mirage Tower's twelve metatiles is used exactly ONCE.
                  local counts2 = ctx.metatileCounts()
                  if not (st and st.overhead and (st.solid or 0) >= 0.9
                          and mm and (counts2[mm] or 0) <= RARE_BUILD) then
                    break
                  end
                  t = ny
                  grew = grew + 1
                end
              end
              if grew > overheadRows then overheadRows = grew end
              -- A COLUMN OF FOLIAGE IS NOT A COLUMN OF THE BUILDING.
              --
              -- MOTIVATED BY FORTREE CITY'S SIX TREE HUTS.
              --
              -- The walk takes a neighbouring column while its blocked run
              -- tops out within a row of the door column's, and the art trim
              -- above has usually cut both to their bottom row -- so the test
              -- reduces to "is this cell blocked, on the same row".  In a
              -- wood every cell is.  Fortree's hut at (10,3) claimed eleven
              -- columns, x = 5..15: five cells of hut and THIRTEEN of canopy,
              -- and the same for five of the town's nine structures -- 55 of
              -- its 138 claimed cells.  Because the late building pass gives
              -- every cell of a footprint the building's own run
              -- (`S.buildingRestored`), the whole of Fortree's north edge
              -- meshed as one continuous 16px wall of hut standing at 36,
              -- from x = 5 to x = 16, with forest art painted on it.
              --
              -- `RARE_BUILD` cannot separate them here and the comment on it
              -- says why: it is "far below the tens and hundreds that
              -- landscape tiles at", and this map draws the SAME HUT six
              -- times, so its art tiles 6 to 13 times while the forest beside
              -- it tiles 12 to 156.  The two ranges overlap and no threshold
              -- on that count can cut between them.
              --
              -- The drawing separates them and the rest of the build already
              -- reads it: `roleAt` calls these cells `tree`, `buildScenery`
              -- meshes them as crowns, and the roofline levelling twenty
              -- lines below refuses to fill a column through a leafy row for
              -- exactly this reason -- "foliage is a hull, never a storey".
              -- The column walk was the one reader that disagreed.  So a
              -- FLANK column every row of which is drawn as foliage is not
              -- the building, and the walk stops there.
              --
              -- ...AND A DOOR CUT THROUGH FOLIAGE IS NOT A DOOR IN A
              -- BUILDING.  Applied to the door's own column as well, so a
              -- warp Emerald cuts into a wall of trees claims nothing and
              -- never becomes a building -- Route 104's two entrances to
              -- Petalburg Woods, (10,38)/(11,38) and (32,42)/(33,42), and
              -- Route 118's tunnel mouth.  The cave-mouth rule at the end of
              -- this function is already trying to throw those away -- "a
              -- cave mouth, a woods entrance, an underwater tunnel or bare
              -- cliff", twenty of them -- and it does it by counting how
              -- often the footprint's art is laid, which is the same count
              -- that cannot see Fortree.  The drawing says it directly.
              --
              -- OUTDOORS ONLY, with the two rules below it: indoors this
              -- function is answering about rooms and the warps between them
              -- and there is no foliage to confuse.
              --
              -- MEASURED over all 518 maps -- claimed cells 7,363 -> 7,270,
              -- buildings 461 -> 461, five maps moved:
              --
              --   FortreeCity      138 -> 83   the six huts and the Mart
              --   Route104          85 -> 53   the Petalburg Woods entrance
              --                                at (10,38), 32 cells of forest
              --                                that had been given a facade
              --   LavaridgeTown    116 -> 110  the house at (15,5), whose east
              --                                column is six rows of forest
              --   BattleFrontier_
              --     OutsideWest    344 -> 342
              --   PetalburgWoods     0 ->   2  the reverse: with its flanks
              --                                gone the (14,5) warp's own two
              --                                cells stop looking like a cave
              --                                mouth to the rule below.  Every
              --                                height on that map is identical
              --                                either way.
              --
              -- Zero cells that `roleAt` calls `tree` are left inside any
              -- footprint in Hoenn (Fortree had 55).
              if ctx.outdoor then
                local allLeaf = true
                for y = t, b do
                  if not foliageCell(cx, y) then allLeaf = false break end
                end
                if allLeaf then return false end
              end
              taken[#taken + 1] = { cx = cx, top = t, raw = rawTop }
              for y = t, b do
                local k = y * 8192 + cx
                if not built.cell[k] then
                  built.cell[k] = #built.list + 1
                  cells[#cells + 1] = { cx, y }
                end
              end
              return true
            end
            take(wx)
            for dx = 1, 5 do if not take(wx + dx) then break end end
            for dx = 1, 5 do if not take(wx - dx) then break end end

            -- THE ROWS THE WALK ITSELF FOUND, before the three passes below
            -- widen the footprint.  The cave-mouth rule at the end of this
            -- function asks whether the building is ONE row deep, and that is
            -- a question about what the walk found of the building's own art
            -- -- not about the frontage the shopfront pass adds under it.
            -- Read only outdoors, where that frontage rule applies; indoors
            -- the drop test keeps the footprint it always had.
            local walkY0 = nil
            for _, c in ipairs(cells) do
              if walkY0 == nil or c[2] < walkY0 then walkY0 = c[2] end
            end

            -- A ROOF'S APEX IS BESPOKE ART, AND BESPOKE ART APPEARS ONCE.
            --
            -- Sootopolis' Pokemon Center is built at (42,28)-(45,31) and the
            -- detection stopped a row short: `roofAt` wants the top half drawn
            -- above the player filling three quarters of the cell, and the
            -- orange apex row (metatiles 635-638) is drawn in the BOTTOM layer
            -- at 0.39-0.86 solid, so it failed both halves of the test.  Those
            -- four cells came back `shelf` -- landscape -- so the Center's roof
            -- was given a course of cliff, climbed with the rock, and drawn as
            -- a stone ledge over its own facade.
            --
            -- There is no art signal for it; both roof tests measure the top
            -- layer and the apex is not in it.  What separates it is that
            -- LANDSCAPE TILES, and a roof does not: 635, 636, 637 and 638
            -- appear exactly once each on the whole map, side by side across
            -- the building's own columns, a different metatile per cell.  The
            -- stone behind the Center -- the case the roof test was added for
            -- -- is 605 twenty-two times and 577 fifty-four, and is refused by
            -- the same rule.
            --
            -- ...AND THE SAME RULE FINDS THE HALF OF THE MART THAT WAS LOST.
            --
            -- Sootopolis' Pokemon Mart at (16,26)-(19,29) draws no roof the
            -- top-layer test can see either, so the end-matching fallback ran
            -- and it matched only the two columns whose blocked runs happen to
            -- end level with the door's: x=16 and 17 came out `wall`, x=18 and
            -- 19 came out `shelf` and `cliff`.  Half the shop was landscape --
            -- given a course, climbed with the rock and drawn as stone.
            --
            -- Its cells are bespoke too: 620 twice, and 50, 51, 58, 59, 621,
            -- 631, 65, 66 once each.  The stone beside the buildings is 605
            -- twenty-two times, 577 fifty-four, 737 two hundred and ninety-
            -- nine.  Four is well inside that gap and leaves room for a motif
            -- a building repeats across its own frontage.
            --
            -- Bounded to three columns each way, for the same reason the rows
            -- are bounded to two: past that this is following a mass.
            local RARE = 4
            do
              local counts = ctx.metatileCounts()
              local x0, x1, ytop, ybot = nil, nil, nil, nil
              for _, c in ipairs(cells) do
                if x0 == nil or c[1] < x0 then x0 = c[1] end
                if x1 == nil or c[1] > x1 then x1 = c[1] end
                if ytop == nil or c[2] < ytop then ytop = c[2] end
                if ybot == nil or c[2] > ybot then ybot = c[2] end
              end
              -- PER COLUMN, ITS OWN RUN -- not the building's bounding box.
              -- The Mart's two found columns run six rows deep because the
              -- stone behind the shop joins them, so testing the bounding box
              -- asked whether x=18 was blocked at y=23 (it is open pavement)
              -- and refused the column.  Each column answers for the run its
              -- OWN blocked mass makes beside the door, exactly as `take`
              -- does.
              local function grab(cx)
                if cx < 0 or cx >= width then return false end
                local t, b = runAbove(cx, wy)
                if not t then return false end
                for cy2 = t, b do
                  local mm = ctx.metatileAt(cx, cy2)
                  if mm == nil or (counts[mm] or 0) > RARE then return false end
                end
                for cy2 = t, b do
                  local k = cy2 * 8192 + cx
                  if not built.cell[k] then
                    built.cell[k] = #built.list + 1
                    cells[#cells + 1] = { cx, cy2 }
                  end
                end
                -- ...AND A COLUMN THE BESPOKE-ART WALK CLAIMED IS ONE OF THE
                -- BUILDING'S COLUMNS.  It votes in "A BUILDING HAS ONE
                -- ROOFLINE" below, which now runs after this walk instead of
                -- before it -- see the note there.
                taken[#taken + 1] = { cx = cx, top = t, raw = t }
                return true
              end
              if x1 then
                for d2 = 1, 3 do if not grab(x1 + d2) then break end end
                for d2 = 1, 3 do if not grab(x0 - d2) then break end end
              end
              -- ...AND THE SHOPFRONT THE DOOR IS SET INTO.
              --
              -- `runAbove` walks the blocked mass ABOVE the warp, so the row
              -- the door itself is in is never part of the building.  For the
              -- Mart that is its whole white frontage -- (16,29) to (19,29),
              -- the wall carrying the MART sign -- which came back `cliff` and
              -- was drawn as rock under its own shop.  The same rare-art test
              -- guards it: 639 twice, 65, 66 and 631 once each, against ground
              -- metatiles that run to the hundreds.
              do
                local nx0, nx1 = nil, nil
                for _, c in ipairs(cells) do
                  if nx0 == nil or c[1] < nx0 then nx0 = c[1] end
                  if nx1 == nil or c[1] > nx1 then nx1 = c[1] end
                end
                -- ...AND A FRONTAGE UNDER THE BUILDING IS THE BUILDING,
                -- WHATEVER ELSE THE MAP DRAWS WITH THE SAME BRICK.
                --
                -- The rare-art guard is the cave-mouth guard, and it costs
                -- the frontage of every building whose ground-floor course
                -- is drawn with the generic house set: RustboroCity's
                -- Trainer School is 577 across row 30 -- laid 22 times on
                -- this map, because every other house uses it too -- so six
                -- cells of its own shopfront stayed landscape and sat at 32
                -- under a roofline of 72.
                --
                -- A cell of that row with a claimed cell of THIS building
                -- directly over it is under the mass the door was cut into;
                -- it cannot be a cave mouth, because a cave mouth's whole
                -- footprint is the one arch row and there is nothing of it
                -- above.  (The `drop` rule below still tests exactly that.)
                local mine = #built.list + 1
                if nx0 then
                  for cx = nx0, nx1 do
                    local k = wy * 8192 + cx
                    if not built.cell[k] and ctx.blockedAt(cx, wy) then
                      local mm = ctx.metatileAt(cx, wy)
                      local under = ctx.outdoor and wy > 0
                        and built.cell[(wy - 1) * 8192 + cx] == mine
                      if mm and ((counts[mm] or 0) <= RARE or under) then
                        built.cell[k] = mine
                        cells[#cells + 1] = { cx, wy }
                      end
                    end
                  end
                end
              end
            end
            -- ...AND IT RUNS AFTER THE BESPOKE-ART WALK, NOT BEFORE IT.
            --
            -- MOTIVATED BY SLATEPORT'S OCEANIC MUSEUM, (28..33, 22..26),
            -- reported as "part of the museum roof is caved in".  The museum
            -- has TWO front doors, (30,26) and (31,26), and Emerald puts the
            -- above-player layer over their two columns only on the canopy
            -- row y = 25 -- the four rows of pillar above it are drawn
            -- face-on.  So `roofTop` answered 25 for the door columns, `take`
            -- cut each to its own stated roofline and claimed ONE row, and
            -- the four columns that carry the building's full height came in
            -- through the bespoke-art widening below instead.  This rule read
            -- `taken`, which held only the two door columns, so `tMin` was 25
            -- and it filled nothing: (30,22..24) and (31,22..24) were never
            -- claimed at all.  They stayed landscape, `capGen3Rock` gave them
            -- 14 and 16 against a roofline of 64, and the middle of the roof
            -- came out as a rectangular hole between two full-height ends --
            -- which is the caved-in section in the report, exactly.
            --
            -- Nothing about the rule itself changes.  It runs where its own
            -- comment says it should, once the walk has found every column of
            -- the building, and its guard -- a column may only be filled down
            -- to its OWN blocked run -- still holds, so it can still only
            -- claim more of what the walk already stood on, never less, and
            -- never anything walkable or beyond the mass.
            -- A BUILDING HAS ONE ROOFLINE, AND THE ART WALK GIVES ITS
            -- COLUMNS SEVERAL.
            --
            -- "A building's art is BESPOKE and the landscape it backs onto
            -- TILES" is a fact about a MAP, and it is applied above per
            -- COLUMN, one metatile at a time, with the threshold at four.  A
            -- building four cells wide that repeats one wall metatile across
            -- its own frontage already passes four -- and Emerald reuses the
            -- generic house set across every building on a map, so the same
            -- brickwork is laid a dozen times over.  The walk then eats the
            -- middle columns of a building down to its last row while the end
            -- columns, whose corner pieces are bespoke, keep all of theirs.
            --
            -- RustboroCity's Trainer School, door (13,30).  Every column's
            -- blocked run is rows 26..29; the wall band 553/561/570 is laid
            -- 15 to 19 times on this map, so columns 10..15 were trimmed to
            -- row 29 and columns 9, 16 and 17 kept 26..29.  The six middle
            -- columns were never founded, kept `role = shelf`, and settled at
            -- 32 against a roofline of 72 -- a nine-cell hole, forty pixels
            -- deep, in the middle of the school.  Eight of Rustboro's eleven
            -- buildings are hollow like that, 52 cells in all.
            --
            -- The trim is kept -- it is what stops a shop eating the cliff
            -- behind it -- but it decides ONE cut for the building, the
            -- highest any of its columns reached, exactly as
            -- `foundGen3Buildings` levels one roofline over the columns it
            -- measured.  A column can only be filled down to its OWN blocked
            -- run, so nothing walkable and nothing beyond the mass is taken:
            -- this can only ever claim more of what the walk already stood
            -- on, never less.
            --
            -- ...AND A CROWN IS NOT A COURSE.  Emerald cuts the warp into
            -- Petalburg Woods through a wall of trees -- Route104 (4..16,
            -- 29..39) is metatile 199 over and over, `role = tree` on every
            -- cell -- and the art trim leaves that door two rows because a
            -- tree tiles.  Levelled without this the walk claimed 86 cells of
            -- forest as one building and would have given it a facade and a
            -- roof.  Foliage is a hull (`buildCylinders`), never a storey, so
            -- a column fills from its own top upward and stops at the first
            -- leafy row -- the same `leafy` test the railing carve and the
            -- roof fold already refuse art on.
            --
            -- OUTDOORS ONLY.  Indoors `ctx.buildings` is answering about
            -- rooms and the warps between them, where a "building" is a wall
            -- with a sliding door in it and there is no street and no
            -- roofline; the two rules here are about a house seen from
            -- outside and measurably churn the indoor answer (PetalburgCity's
            -- Gym, twelve interior doors, and eight cave maps).
            --
            -- In-game location: the Trainer School and the Pokemon Center in
            -- Rustboro; the same shape in Mauville, Lilycove and Lavaridge.
            if ctx.outdoor and #taken > 1 then
              local anL = Gen3.analyse(map.tileset)
              local function leafyAt(cx, cy)
                local mm = ctx.metatileAt(cx, cy)
                local st = mm and anL and anL.stats and anL.stats[mm]
                return st ~= nil and st.leafy == true
              end
              local tMin = nil
              for _, e in ipairs(taken) do
                if tMin == nil or e.top < tMin then tMin = e.top end
              end
              for _, e in ipairs(taken) do
                local newTop = tMin
                if newTop < e.raw then newTop = e.raw end
                for y = e.top - 1, newTop, -1 do
                  if leafyAt(e.cx, y) then break end
                  local k = y * 8192 + e.cx
                  if not built.cell[k] then
                    built.cell[k] = #built.list + 1
                    cells[#cells + 1] = { e.cx, y }
                  end
                end
              end
            end
            -- Bounded to two rows: past that this is following a mass, which
            -- is the failure the roof rule above exists to prevent.
            do
              local counts = ctx.metatileCounts()
              local x0, x1, top = nil, nil, nil
              for _, c in ipairs(cells) do
                if x0 == nil or c[1] < x0 then x0 = c[1] end
                if x1 == nil or c[1] > x1 then x1 = c[1] end
              end
              for _, c in ipairs(cells) do
                if c[1] >= x0 and c[1] <= x1 then
                  if top == nil or c[2] < top then top = c[2] end
                end
              end
              for _ = 1, 2 do
                if not top or top <= 0 then break end
                local row, ok = top - 1, true
                for cx = x0, x1 do
                  if not ctx.blockedAt(cx, row) then ok = false break end
                  local mm = ctx.metatileAt(cx, row)
                  if mm == nil or (counts[mm] or 0) ~= 1 then ok = false break end
                end
                if not ok then break end
                for cx = x0, x1 do
                  local k = row * 8192 + cx
                  if not built.cell[k] then
                    built.cell[k] = #built.list + 1
                    cells[#cells + 1] = { cx, row }
                  end
                end
                top = row
              end
            end
            -- A CAVE MOUTH IS A HOLE IN A MASS, NOT A BUILDING.
            --
            -- Emerald gives a cave entrance the same behaviour byte as a
            -- front door -- 0x60 MB_NON_ANIMATED_DOOR -- so a warp cut into a
            -- cliff arrives here looking exactly like a shop.  The bespoke
            -- walk above then eats the whole mountain behind it, because the
            -- mountain's art is common, and leaves ONE row: the arch.  That
            -- row was founded as a building, given a facade and stood on the
            -- street, and the mountain behind it was drawn flat around it.
            -- Route 112's Fiery Path mouth at (22,10) is the case the player
            -- sees: a doorway on a box, with no mountain over it.
            --
            -- Four things are true of a doorway in terrain and of nothing
            -- else in Hoenn:
            --
            --   the footprint is ONE row -- the walk found no second row of
            --     the building's own art;
            --   the cartridge states no roof over it -- `roofTop` is where
            --     Emerald says "this is a building", and a cliff has none;
            --   the mass CONTINUES above the footprint -- for a building the
            --     next row up is sky, for an arch it is more mountain;
            --   and the art is the landscape's -- most of the footprint is
            --     metatiles the map places dozens or hundreds of times, where
            --     a building's art is placed once or twice.
            --
            -- Region-wide that is 20 entries and every one is a cave mouth, a
            -- woods entrance, an underwater tunnel or bare cliff.  It leaves
            -- Pacifidlog's floating huts (roofed, nothing above them) and all
            -- five of Fortree's tree houses (their own art) standing.
            --
            -- ...ASKED OF THE ROWS THE WALK FOUND, NOT OF THE FRONTAGE.
            --
            -- "The footprint is ONE row" is a statement about the building's
            -- own art, and the shopfront rule above now adds the door's own
            -- row under any mass the walk claimed.  Counted with it every
            -- cave mouth in Hoenn is two rows deep and none of them drops:
            -- Route112's Fiery Path, Petalburg Woods and Route118's tunnel
            -- all came back as buildings.  So the test reads the walk's rows
            -- -- `walkY0` to the row above the door -- and the cells in them.
            local drop = false
            if #cells > 0 and not t0r then
              local y0, y1, rare, above, nc = nil, nil, 0, 0, 0
              local counts = ctx.metatileCounts()
              local yCut = (ctx.outdoor and walkY0) and (wy - 1) or nil
              for _, c in ipairs(cells) do
                if yCut == nil or c[2] <= yCut then
                  if y0 == nil or c[2] < y0 then y0 = c[2] end
                  if y1 == nil or c[2] > y1 then y1 = c[2] end
                  nc = nc + 1
                  local mm = ctx.metatileAt(c[1], c[2])
                  if mm and (counts[mm] or 0) <= RARE_BUILD * 8 then
                    rare = rare + 1
                  end
                end
              end
              if y0 ~= nil and y0 == y1 and y0 > 0 then
                for _, c in ipairs(cells) do
                  if c[2] == y0 then
                    local okA, bk = pcall(ctx.blockedAt, c[1], y0 - 1)
                    if okA and bk then above = above + 1 end
                  end
                end
                if above * 2 >= nc and rare * 5 < nc * 2 then
                  drop = true
                end
              end
            end
            if drop then
              for _, c in ipairs(cells) do
                built.cell[c[2] * 8192 + c[1]] = nil
              end
              cells = {}
            end
            -- ...AND A SPAN THE CARTRIDGE CALLS A BRIDGE IS NOT PART OF A
            -- BUILDING.
            --
            -- MOTIVATED BY ROUTE 110'S TWO CYCLING ROAD GATE HOUSES AND THE
            -- ROAD THEY GATE.  The road's own blocked pieces -- its parapet
            -- and its abutment walls -- flood-join a gate house's mass with
            -- nothing between them, so the column walk swept them in: the
            -- southern gate house at (9..13, 61..66) claimed (11,58), (11,59)
            -- and (11,60), three cells of the raised road's parapet standing
            -- out over open sea, and the "a building's box covers its whole
            -- footprint" restore in Structures then handed all three the gate
            -- house's own run.  That is 96px of pink facade standing on the
            -- causeway two courses above the water, which is the grey tower
            -- behind the gate house in the report.
            --
            -- Emerald states the difference outright and this file already
            -- reads it for the deck pass: `bridge_lift` is keyed on the four
            -- MB_BRIDGE_* behaviours plus the bike bridge and the Fortree
            -- rope walk.  A cell carrying one of those is ROAD -- something
            -- you ride over -- whatever mass it is welded to.
            --
            -- MEASURED over all 518 maps: of 7,362 claimed footprint cells,
            -- FOUR carry a bridge behaviour, and all four are on Route 110
            -- and all four are 0x70 MB_BRIDGE_OVER_OCEAN -- the three parapet
            -- cells above and (21,86), a piece of the road's west abutment
            -- that the rare-art widening reached from the northern gate
            -- house.  Nothing else in Hoenn loses a cell, and Pacifidlog's
            -- rafts and Fortree's huts are untouched because a walkable cell
            -- can never enter a footprint in the first place (`runAbove`
            -- walks blocked cells and the shopfront rule tests `blockedAt`).
            if #cells > 0 then
              local keep = {}
              for _, c in ipairs(cells) do
                local mm = ctx.metatileAt(c[1], c[2])
                local span = false
                if mm ~= nil then
                  local okB, bb = pcall(ctx.attributes, mm)
                  if okB and bb and ctx.bridgeLift
                     and ctx.bridgeLift[bb] ~= nil then
                    span = true
                  end
                end
                if span then
                  built.cell[c[2] * 8192 + c[1]] = nil
                else
                  keep[#keep + 1] = c
                end
              end
              cells = keep
            end
            if #cells > 0 then
              -- HOW MANY ROWS OF THIS BUILDING ARE DRAWN ABOVE THE PLAYER.
              --
              -- Recorded so `foundGen3Buildings` can give the facade the
              -- height the drawing actually has.  A run measures its own art
              -- extent, and the walk-behind rows carry no run at all -- they
              -- are walkable -- so without this the Mirage Tower's six rows
              -- still measured the two blocked ones: `h=32 peak=48` against a
              -- drawing 96 tall.
              built.list[#built.list + 1] = { cells = cells, door = { wx, wy },
                                              overheadRows = overheadRows,
                                              roofed = t0r ~= nil }
            end
          end
        end
      end
      return built
    end
    function ctx.isBuildingCell(cx, cy)
      local b = ctx.buildings()
      return b.cell[cy * 8192 + cx] ~= nil
    end
  end

  ctxCache[map] = ctx

  say("map", "%s (%s): %d metatiles, %d elevation level(s)%s",
      tostring(map.id or "?"), ctx.mapName or "unnamed", ctx.metatiles, levels,
      collisionCells and "" or " (no per-cell collision)")

  return ctx
end

-- ---------------------------------------------------------------------------
-- THE TEXTURE
--
-- ONE sheet, and this is a design decision rather than a shortcut.
--
-- Gen 3 bakes a pair into TWO sheets because the flat game draws them either
-- side of the player: the bottom half is what you walk in front of and the
-- top half is what you walk behind.  That split is a two-dimensional trick
-- for depicting height on a map that has none.  A diorama has height, and a
-- depth buffer -- a treetop drawn over the player on the GBA is simply UP
-- here, and the geometry puts the player behind it without being told.
--
-- So the two sheets are composited into one texture and the top layer is read
-- instead as a HEIGHT SIGNAL: a metatile whose top half is drawn above the
-- player is a metatile with something standing on it (Gen3.classAt).  The
-- alternative -- a second mesh with its own texture drawn after the character
-- pass -- would reproduce the flat game's draw order faithfully and look
-- wrong from every camera angle except straight down.
--
-- Composited on the GPU from the engine's own baked sheets rather than
-- re-baked on the CPU, so the diorama and the flat map can never disagree
-- about what a metatile looks like.  Once per pair, cached.
-- ---------------------------------------------------------------------------

local atlasCache = {}
local atlasDataCache = {}
local atlasInfoCache = {}
local artCache = {}
local shapeCache = {}

-- The Gen3Tiles instance for a pair, from whichever source has one.
-- The Gen3Tiles instance for a PAIR. Keyed by the tileset alone, because the
-- atlas is a property of the pair and not of any one map -- `Structures`
-- reaches it with nothing but a tileset record in hand.
local function tilesForTileset(tileset)
  local okTR, TileRenderer = pcall(require, "src.render.TileRenderer")
  if okTR and TileRenderer and type(TileRenderer.gen3SheetsFor) == "function" then
    local data = engineData()
    local okBake, baked = pcall(TileRenderer.gen3SheetsFor, tileset, data,
                                data and data.constants
                                and data.constants.gen3Layout)
    if okBake and baked and baked.tiles then return baked.tiles end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- THE ATLAS IS RE-LAID AS AN ORDINARY 8px TILE SHEET.
--
-- This is the most useful thing in the file, and it is a layout change rather
-- than a rendering one.
--
-- Gen3Tiles composites a pair into a sheet of 16x16 METATILES. Everything in
-- this mod that makes a SHAPE -- the tree hulls, the roof massing, the
-- per-pixel props, the void test, grass, flowers, relief, bookcases -- reads
-- the atlas as a grid of 8x8 TILES at `(t % perRow) * 8`, in sixty-three
-- places across Structures and Buildings. Two incompatible layouts, and the
-- consequence was not a wrong picture but NO SHAPE AT ALL: `Structures.pixels`
-- answered nil on Gen 3, every one of those passes is gated on `if data then`,
-- and all of them quietly skipped. Every tree and every house fell through to
-- a plain measured box. That is the "everything is boxy" report, entire.
--
-- So instead of teaching sixty-three sites a second layout, the sheet is
-- emitted in the layout they already speak: metatile `m` quadrant `q` lands at
-- synthetic tile id `4m + q`, and tile `t` sits at `(t % 16) * 8` across and
-- `floor(t / 16) * 8` down -- exactly where a Gen 1 tile id would put it. The
-- four quadrants of a cell are always four CONSECUTIVE tiles in one row
-- (4m mod 16 is always 0, 4, 8 or 12), so nothing ever straddles a row.
--
-- Adjacency in the sheet carries no meaning to any of these passes -- they
-- compose shapes from `map:tileAt`, never from where two tiles happen to sit
-- next to each other -- which is what makes the relabelling safe.
--
-- The transform runs inside the plot callback, so there is no intermediate
-- buffer: Gen3Tiles hands out metatile-sheet coordinates and they are mapped
-- to tile-sheet coordinates on the way past.
-- ---------------------------------------------------------------------------
-- WHAT A METATILE IS A PICTURE OF.
--
-- Measured on a real Littleroot, the behaviour byte resolves the WHOLE MAP to
-- three classes: wall, ground, water. Not one tree, roof, fence, sign or
-- flower -- because Emerald writes MB_NORMAL on the trees, the houses, the
-- roofs, the fences and the signs alike. The byte answers "what kind of
-- surface is this", and scenery is not a kind of surface. Gen 1 and Gen 2 get
-- away without such a byte because this mod reads their ART; on Gen 3 the art
-- was the one thing nothing looked at, so every object in Hoenn meshed as the
-- box its collision bit implied. That is the boxiness, entire, and no amount
-- of hand-pinning seventy-four tilesets would have fixed it.
--
-- So: read the art. Two facts about a Gen 3 metatile make this far easier
-- than the Gen 1 equivalent.
--
-- ONE. EMERALD DRAWS AN OBJECT ON LAYER 2 OVER THE GROUND ON LAYER 1. A house
-- roof metatile's bottom layer is plain grass -- pixel for pixel the same
-- grass as the empty field beside it -- and the roof is the top layer, drawn
-- with real transparency around its edges. So for everything drawn that way
-- the SILHOUETTE ALREADY EXISTS; the composite is what destroys it, by
-- painting the two layers into one opaque sheet. Splitting them back out is
-- all the outline detection a roof, an awning, a sign or a fence needs.
--
-- TWO. THE GROUND COLOURS IDENTIFY THEMSELVES. Because layer 1 under a full
-- layer-2 object is by construction ground, the set of ground colours can be
-- read off rather than guessed at: take the layer-1 palette of every metatile
-- whose top layer is nearly full, and that is the tileset's own answer to
-- "what does the floor look like here" -- grass in the fields, sand on the
-- beach, rock in a cave, floorboards in a house. No colour constants, no
-- greenness heuristic, nothing to retune per tileset.
--
-- Those two together give the SHAPE SURFACE: the same bake as the texture
-- atlas, except that a layer-1 pixel painted in a ground colour, with no
-- layer-2 art over it, is written TRANSPARENT. Every pixel pass in Structures
-- and Buildings tests alpha to find background -- `a == 0 and "off"` -- so
-- with that one change the tree hulls, the roof massing, the per-pixel props,
-- the void test, grass, flowers and relief all start seeing real outlines on
-- Gen 3 instead of a wall-to-wall opaque rectangle that carves to nothing.
--
-- The texture atlas stays fully opaque. These are two surfaces on purpose:
-- one is what the world is painted with, the other is what its shape is read
-- from, and a hole in the first is a hole in the ground.

-- a palette colour, as an exact key -- Gen 3 art is indexed, so equality is
-- exact and there is no distance threshold to pick
local function colourKey(r, g, b)
  return r * 65536 + g * 256 + b
end

-- A metatile's top layer is "full" when it covers three quarters of the cell.
-- Below that it is an object with a silhouette (a sign, a fence, an awning)
-- and its bottom layer is not necessarily ground.
local GROUND_SAMPLE = 192      -- of 256

local function analyse(tileset)
  local key = tostring(tileset.id)
  local hit = artCache[key]
  if hit ~= nil then return hit or nil end
  artCache[key] = false

  local tiles = tilesForTileset(tileset)
  if not tiles then return nil end

  local stats = {}
  local function rec(m)
    local s = stats[m]
    if not s then
      s = { n1 = 0, n2 = 0, solidN = 0, r = 0, g = 0, b = 0,
            leaf = 0, warm = 0, dark = 0, bright = 0,
            top2 = 0, bot2 = 0, topSolid = 0, botSolid = 0, rows2 = {} }
      stats[m] = s
    end
    return s
  end
  local function metaAt(x, y)
    return math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
  end

  -- PASS ONE: the top layer. Occupancy per metatile, which decides both what
  -- counts as a ground sample below and what has a silhouette at all; and the
  -- colour histogram of OBJECT art, which is the guard against a ground
  -- colour that is also something's paint.
  local objectHist = {}
  local okTop = pcall(tiles.bakeLayer, tiles, 2, function(x, y, r, g, b)
    local s = rec(metaAt(x, y))
    s.n2 = s.n2 + 1
    local row = y % CELL
    if row < 8 then s.top2 = s.top2 + 1 else s.bot2 = s.bot2 + 1 end
    s.rows2[row] = (s.rows2[row] or 0) + 1
    local c = colourKey(r, g, b)
    objectHist[c] = (objectHist[c] or 0) + 1
  end)
  if not okTop then return nil end

  -- PASS TWO: the bottom layer, for the GROUND histogram only -- gathered
  -- from under a full top layer, where the bottom is ground by construction.
  local groundHist = {}
  -- edge strips per metatile, for the seamlessness test below
  local edge = {}
  local function edgeOf(m)
    local e = edge[m]
    if not e then e = { L = {}, R = {}, T = {}, B = {}, all = {} } edge[m] = e end
    return e
  end
  local okBot = pcall(tiles.bakeLayer, tiles, 1, function(x, y, r, g, b)
    local m = metaAt(x, y)
    local s = rec(m)
    s.n1 = s.n1 + 1
    local c = colourKey(r, g, b)
    if s.n2 >= GROUND_SAMPLE then
      groundHist[c] = (groundHist[c] or 0) + 1
    end
    local lx, ly = x % CELL, y % CELL
    local e = edgeOf(m)
    if lx == 0 then e.L[ly] = c elseif lx == CELL - 1 then e.R[ly] = c end
    if ly == 0 then e.T[lx] = c elseif ly == CELL - 1 then e.B[lx] = c end
    e.all[#e.all + 1] = c
  end)
  if not okBot then return nil end

  -- WHICH METATILES TILE. A floor repeats across its neighbours, so the
  -- colours down its left edge continue the ones down its right, and its top
  -- row continues its bottom. Compared as SEQUENCES, not as sets, because a
  -- wall and a floor can share a palette while only one of them lines up.
  local seamlessHist = {}
  for m, e in pairs(edge) do
    local st = stats[m]
    if st and st.n2 == 0 and #e.all >= 256 then
      local okH, okV = true, true
      for i = 0, CELL - 1 do
        if e.L[i] ~= e.R[i] then okH = false end
        if e.T[i] ~= e.B[i] then okV = false end
      end
      -- TILING IS NECESSARY, NOT SUFFICIENT. Two things also tile: a flat
      -- field of one colour, and foliage drawn as a seamless mass (a hedge,
      -- the interior of a forest). Neither is floor, and swallowing either
      -- one into the background dissolves the object it belongs to -- a
      -- canopy carved to nothing is a tree that stops existing.
      --
      -- A real floor is PATTERNED (boards, tiles, carpet weave, gravel), so
      -- it carries at least a few palette entries; and it is not green with
      -- the blue taken out, which is the foliage signature used everywhere
      -- else in this file.
      local distinct, leafish = 0, 0
      if okH and okV then
        local seen = {}
        for _, c in ipairs(e.all) do
          if not seen[c] then seen[c] = true distinct = distinct + 1 end
          local r = math.floor(c / 65536)
          local g = math.floor(c / 256) % 256
          local b = c % 256
          if g > r * 1.10 and g > b * 1.35 then leafish = leafish + 1 end
        end
      end
      if okH and okV and distinct >= 3 and leafish <= #e.all * 0.5 then
        st.seamless = true
        for _, c in ipairs(e.all) do
          seamlessHist[c] = (seamlessHist[c] or 0) + 1
        end
      end
    end
  end

  -- INDOORS THERE IS NOTHING DRAWN ON TOP OF THE FLOOR.
  --
  -- The rule above -- layer 1 under a full layer 2 is ground -- is an outdoor
  -- rule. It works because Emerald paints grass under every roof and awning
  -- in Hoenn. Inside a building the above-player layer is the TOP OF A WALL,
  -- and the layer-1 art beneath it is more wall, so an interior pair yielded
  -- either no ground samples at all or a handful of masonry colours. Measured
  -- across the game: the outdoor pairs carve 20-38% of their sheet, several
  -- indoor ones carve nothing, and a pair with no background set gets no
  -- silhouette -- which is every room in the game meshing furniture as blocks.
  --
  -- A FLOOR TILES AND FURNITURE DOES NOT. That is the other thing a floor is,
  -- and it holds indoors and out: floorboards, carpet, lino, grass and sand
  -- are all drawn to repeat seamlessly across neighbouring cells, so a
  -- metatile's left edge matches its right and its top matches its bottom. A
  -- chair, a bookcase, a sink or a doorway is a single object inside its cell
  -- and matches nothing. So when the layer-2 method comes up short, take the
  -- ground samples from the metatiles that TILE.
  do
    local haveGround = 0
    for _, n in pairs(groundHist) do haveGround = haveGround + n end
    if haveGround < 2048 then
      for c, n in pairs(seamlessHist) do
        groundHist[c] = (groundHist[c] or 0) + n
      end
    end
  end

  -- THE BACKGROUND SET. A colour qualifies when the ground samples use it and
  -- object art does not lean on it -- so the grass under every roof in town
  -- is background, and the green of a hedge that happens to share one entry
  -- with the lawn is not.
  local background, bgCount = {}, 0
  local groundTotal = 0
  for _, n in pairs(groundHist) do groundTotal = groundTotal + n end
  if groundTotal > 0 then
    for c, n in pairs(groundHist) do
      if n >= groundTotal * 0.002 and (objectHist[c] or 0) < n * 0.5 then
        background[c] = true
        bgCount = bgCount + 1
      end
    end
  end

  -- PASS THREE: the OBJECT's own colours -- every layer-2 pixel, and every
  -- layer-1 pixel that is not background.
  --
  -- Measuring these over the raw bottom layer instead was wrong in exactly
  -- the cases that matter most. A tree drawn as a canopy on layer 2 over
  -- grass on layer 1 came out with the mean colour of GRASS and read as not
  -- leafy: the one metatile in Littleroot that is nothing but foliage was the
  -- one the foliage test missed. Colour statistics have to be taken over the
  -- pixels that are the thing.
  local function tally(x, y, r, g, b, layer)
    local s = rec(metaAt(x, y))
    if layer == 1 and background[colourKey(r, g, b)] then return end
    s.solidN = s.solidN + 1
    if (y % CELL) < 8 then s.topSolid = s.topSolid + 1
    else s.botSolid = s.botSolid + 1 end
    local rf, gf, bf = r / 255, g / 255, b / 255
    s.r = s.r + rf; s.g = s.g + gf; s.b = s.b + bf
    -- FOLIAGE IS GREEN WITH THE BLUE TAKEN OUT. Hoenn's ground grass and its
    -- tree canopies are both green and a hue test cannot tell them apart --
    -- but the grass is a bright yellow-green with a strong blue component
    -- (0.46/0.77/0.65) and the canopy a deep one with almost none
    -- (0.39/0.67/0.33). Blue against green separates them with a wide margin
    -- on every outdoor tileset in the game.
    if g > r * 1.10 and g > b * 1.35 then
      s.leaf = s.leaf + 1
      -- ...and WHICH LAYER it was drawn on. A tree overhanging a roof is
      -- foliage on the ABOVE-PLAYER layer over a structure below; a hedge
      -- standing against a wall is foliage on the layer the wall is on.
      -- Both are part-leaf metatiles and only the layer tells them apart.
      if layer == 2 then s.leaf2 = (s.leaf2 or 0) + 1 end
    end
    if r > g * 1.05 and r > b * 1.10 then s.warm = s.warm + 1 end
    local mx = math.max(rf, gf, bf)
    if mx < 0.35 then s.dark = s.dark + 1 end
    if mx > 0.80 then s.bright = s.bright + 1 end
  end
  pcall(tiles.bakeLayer, tiles, 1, function(x, y, r, g, b)
    tally(x, y, r, g, b, 1)
  end)
  pcall(tiles.bakeLayer, tiles, 2, function(x, y, r, g, b)
    tally(x, y, r, g, b, 2)
  end)

  local art = { stats = stats, background = background,
                backgroundColours = bgCount, groundSamples = groundTotal,
                tileset = key }
  for _, s in pairs(stats) do
    local n = s.solidN > 0 and s.solidN or 1
    s.mr, s.mg, s.mb = s.r / n, s.g / n, s.b / n
    -- how much of the 16x16 cell is NOT ground: 0 for an empty field, 1 for a
    -- wall, and the single most useful number in this record
    s.solid = s.solidN / 256
    if s.solid > 1 then s.solid = 1 end
    -- how much of the drawn cell is foliage, kept as a number rather than
    -- only as the `leafy` verdict: a metatile can be part tree and part
    -- something else, and telling those apart needs the fraction (see
    -- Structures' foliage-over-structure repair)
    s.leafFrac = s.leaf / n
    -- of the drawn cell, how much is foliage carried on the above-player
    -- layer (see the tally): the mark of a tree drawn OVER something else
    s.leafFrac2 = (s.leaf2 or 0) / n
    s.leafy = s.solid > 0.25 and s.leafFrac > 0.5 and s.mb < s.mg * 0.66
    s.overhead = s.n2 >= GROUND_SAMPLE
    -- AN OVERHANG: above-player art covering at least half of EVERY row of
    -- the cell. This is what a roof's eave looks like from directly in front
    -- -- the slope juts past the wall it sits on, so the overhang runs the
    -- full height of the cell -- and it is the one measurement that tells the
    -- eave apart from the wall course under it. Measured on gTileset_General:
    -- the eave's flanks (16/18) are half-covered on all sixteen rows, the
    -- wall's own edges (24/26) on five and six. Colour cannot make that call
    -- -- both bands are the same warm red family, and palette-set overlap
    -- puts the eave FURTHER from the roof (0.38) than the siding is (0.44).
    local full2 = 0
    for row = 0, CELL - 1 do
      if (s.rows2[row] or 0) >= 8 then full2 = full2 + 1 end
    end
    s.rowsCovered = full2
    s.overhang = full2 >= CELL - 2
    s.warmth = s.warm / n
    s.darkness = s.dark / n
    s.brightness = s.bright / n
  end
  artCache[key] = art
  return art
end

Gen3.analyse = analyse

--- The art record for one metatile: `{ leafy, overhead, warmth, darkness,
--- mr, mg, mb, n1, n2, top2, bot2, solid }`, or nil when the pair has no
--- pixels to read (a headless host, a bake that failed).
function Gen3.artOf(tileset, metatile)
  local art = analyse(tileset)
  if not art then return nil end
  return art.stats[tonumber(metatile) or -1]
end


local LINEAR_COLS = 16          -- tiles per row, matching `tilesPerRow or 16`

function Gen3.atlasInfoFor(tileset)
  local key = tostring(tileset.id)
  local hit = atlasInfoCache[key]
  if hit then return hit end
  local ids = Gen3.idSpace(tileset, nil)
  local tiles = ids * 4
  local rows = math.ceil(tiles / LINEAR_COLS)
  local info = { perRow = LINEAR_COLS, width = LINEAR_COLS * 8,
                 height = math.max(8, rows * 8), tiles = tiles, metatiles = ids }
  atlasInfoCache[key] = info
  return info
end

function Gen3.atlasInfo(ctx)
  return Gen3.atlasInfoFor(ctx.tileset)
end

-- Tell the tileset record what its atlas looks like, so every reader that asks
-- `tileset.tilesPerRow / imageWidth / imageHeight` -- which is all of them --
-- gets the truth instead of the Gen 1 fallbacks (16 / 128 / 48). Set once, and
-- only fields a Gen 3 pair does not otherwise carry: the engine's own Gen 3
-- path draws from `gen3SheetsFor` and reads none of these.
function Gen3.describe(tileset)
  local info = Gen3.atlasInfoFor(tileset)
  if tileset.tilesPerRow == nil then tileset.tilesPerRow = info.perRow end
  if tileset.imageWidth == nil then tileset.imageWidth = info.width end
  if tileset.imageHeight == nil then tileset.imageHeight = info.height end
  return info
end

local function bakeLinear(tileset)
  local key = tostring(tileset.id)
  local tiles = tilesForTileset(tileset)
  if not tiles then
    warn("noatlas", "no Gen3Tiles for %s -- the world will mesh but has "
         .. "nothing to texture from", key)
    return nil
  end
  if not (love and love.image and love.image.newImageData
          and love.graphics and love.graphics.newImage) then
    return nil
  end
  local info = Gen3.describe(tileset)
  local W, H = info.width, info.height
  local srcCols = SHEET_COLS

  -- ON THE CPU, NOT THROUGH A CANVAS. `atlasFor` is first called from inside
  -- the shadow pass and again between beginScene and endScene, so a foreign
  -- canvas, shader and depth mode are all live; compositing with
  -- love.graphics.draw there runs the sheets through the scene's shader and
  -- yields a texture that is entirely black while reporting total success.
  local okBake, res = pcall(function()
    local surface = love.image.newImageData(W, H)
    local function plot(x, y, r, g, b)
      -- metatile-sheet coordinates in; tile-sheet coordinates out
      local m = math.floor(y / CELL) * srcCols + math.floor(x / CELL)
      local q = math.floor((y % CELL) / TILE) * 2 + math.floor((x % CELL) / TILE)
      local t = m * 4 + q
      local dx = (t % LINEAR_COLS) * TILE + (x % TILE)
      local dy = math.floor(t / LINEAR_COLS) * TILE + (y % TILE)
      if dx >= 0 and dy >= 0 and dx < W and dy < H then
        surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
      end
    end
    tiles:bakeLayer(1, plot)
    tiles:bakeLayer(2, plot)
    local img = love.graphics.newImage(surface)
    pcall(img.setFilter, img, "nearest", "nearest")
    return { image = img, data = surface }
  end)
  if not (okBake and res) then
    warn("atlasfail", "baking the %s atlas failed: %s", key, tostring(res))
    atlasCache[key] = false
    atlasDataCache[key] = false
    return nil
  end
  atlasCache[key] = res.image
  atlasDataCache[key] = res.data
  say("atlas", "relaid %s as an 8px tile sheet -- %d metatiles, %d tiles, "
      .. "%dx%d", key, info.metatiles, info.tiles, W, H)
  return res
end

local function ensureAtlas(tileset)
  local key = tostring(tileset.id)
  if atlasCache[key] ~= nil then
    return atlasCache[key] or nil, atlasDataCache[key] or nil
  end
  local res = bakeLinear(tileset)
  return res and res.image or nil, res and res.data or nil
end

function Gen3.atlasForTileset(tileset)
  if not Gen3.isGen3(tileset) then return nil end
  local img = ensureAtlas(tileset)
  return img
end

-- THE PIXELS, for the shape passes. Same bake, kept rather than discarded --
-- which is the whole unlock: Structures can carve hulls out of Gen 3 art now.
function Gen3.atlasDataForTileset(tileset)
  if not Gen3.isGen3(tileset) then return nil end
  local _, data = ensureAtlas(tileset)
  return data
end

-- ---------------------------------------------------------------------------
-- THE SHAPE SURFACE: the same sheet, with the ground cut out of it.
--
-- Laid out identically to the texture atlas -- same synthetic tile ids, same
-- 8px stride -- so `Structures` and `Buildings` address it with the very same
-- `(t % perRow) * 8` they use everywhere else and never learn it exists.
-- The only difference is alpha, and alpha is the entire point: every pixel
-- pass in this mod finds background by testing `a == 0`.
local function bakeShape(tileset)
  local key = tostring(tileset.id)
  local art = analyse(tileset)
  local tiles = art and tilesForTileset(tileset)
  if not (art and tiles) then
    shapeCache[key] = false
    return nil
  end
  if not (love and love.image and love.image.newImageData) then return nil end

  local info = Gen3.describe(tileset)
  local W, H = info.width, info.height
  local background = art.background
  local stats = art.stats

  local okBake, res = pcall(function()
    local surface = love.image.newImageData(W, H)
    -- the metatile-sheet -> tile-sheet relabelling, shared with the atlas
    local function place(x, y)
      local m = math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
      local q = math.floor((y % CELL) / TILE) * 2 + math.floor((x % CELL) / TILE)
      local t = m * 4 + q
      return (t % LINEAR_COLS) * TILE + (x % TILE),
             math.floor(t / LINEAR_COLS) * TILE + (y % TILE)
    end

    -- bottom layer: ground colours become HOLES, everything else is body
    tiles:bakeLayer(1, function(x, y, r, g, b)
      local dx, dy = place(x, y)
      if dx < 0 or dy < 0 or dx >= W or dy >= H then return end
      if background[colourKey(r, g, b)] then
        surface:setPixel(dx, dy, 0, 0, 0, 0)
      else
        surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
      end
    end)

    -- top layer: object art, always body, drawn over whatever is beneath
    tiles:bakeLayer(2, function(x, y, r, g, b)
      local dx, dy = place(x, y)
      if dx < 0 or dy < 0 or dx >= W or dy >= H then return end
      surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
    end)

    return surface
  end)

  if not (okBake and res) then
    warn("shapefail", "carving the %s shape surface failed: %s", key,
         tostring(res))
    shapeCache[key] = false
    return nil
  end
  shapeCache[key] = res
  say("shape", "carved %s -- %d background colour(s) from %d ground sample "
      .. "pixel(s)", key, art.backgroundColours, art.groundSamples)
  return res
end

--- The pixels the SHAPE passes read: opaque where the art is an object,
--- transparent where it is ground. This is what `Structures.pixels` answers
--- with on Gen 3.
-- ---------------------------------------------------------------------------
-- THE ABOVE-PLAYER LAYER, AS A SILHOUETTE PER METATILE.
--
-- (g3-crown-278.)  Everything else in this file reads the pair COMPOSITED:
-- `bakeLinear` plots layer 1 and then layer 2 into one synthetic tile, which
-- is right for a renderer and wrong for the one question an authored overhead
-- figure has to ask -- WHICH PIXELS ARE THE THING IN FRONT rather than the
-- wall behind it.
--
-- The Game Corner's potted plants are the case.  Emerald draws each plant
-- across two cells: the crown on the ABOVE-PLAYER layer of the wall cell
-- (metatile 559) and the pot in the cell in front (567).  Metatile 559's
-- layer 1 is byte-identical to 538, the plain wall band beside it, and 538's
-- own layer 2 is EMPTY -- so 538 composited IS 559's wall, and the crown is
-- exactly 559's layer 2.
--
-- WHY NOT SUBTRACT THE TWO BAKED METATILES INSTEAD.  Measured, and it is off
-- by two pixels: the difference between 559's composite and 538's is 151 of
-- the crown's 153, because two of the crown's own texels happen to be drawn
-- in the same colour as the wall pixel behind them.  A silhouette two pixels
-- short is two holes in a leaf, so the layer is read directly rather than
-- inferred from a difference.
--
-- Cheap, and only ever asked once per pair: the sheet is walked once, and
-- only metatiles that HAVE above-player art are kept.  On the Game Corner's
-- pair that is 10 metatiles of 1,120, holding 1,615 pixels in total.
local overheadCache = {}

--- Every metatile of a pair that draws on the ABOVE-PLAYER layer, as
--- `{ [metatile] = { [ly * 16 + lx] = true, ... } }`.  Nil when the pair has
--- no tiles to read (a host with no renderer).  Memoised per tileset.
function Gen3.overheadMasks(tileset)
  if not Gen3.isGen3(tileset) then return nil end
  local key = tostring(tileset.id)
  local hit = overheadCache[key]
  if hit ~= nil then return hit or nil end
  local tiles = tilesForTileset(tileset)
  if not tiles then
    overheadCache[key] = false
    return nil
  end
  local out = {}
  local okBake = pcall(tiles.bakeLayer, tiles, 2, function(x, y)
    local m = math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
    local g = out[m]
    if not g then g = {} out[m] = g end
    g[(y % CELL) * CELL + (x % CELL)] = true
  end)
  if not okBake then
    overheadCache[key] = false
    return nil
  end
  overheadCache[key] = out
  return out
end

function Gen3.shapeDataForTileset(tileset)
  -- (Gen3.overheadMasks above reads the layer this one composites away)
  if not Gen3.isGen3(tileset) then return nil end
  local key = tostring(tileset.id)
  local hit = shapeCache[key]
  if hit ~= nil then return hit or nil end
  return bakeShape(tileset)
end

--- The shape surface for ONE MAP: the pair's own carve, plus the colours of
--- the floor this map actually walks on. Keyed by (pair, floor set), so every
--- room sharing a floor shares a surface and the cache stays small.
-- PER-MAP SURFACES ARE BIG AND MUST NOT ACCUMULATE.
--
-- Each one is a full copy of the pair's sheet -- 128 x 2440 is three hundred
-- thousand pixels -- and there is one per distinct FLOOR SET, not per pair.
-- Left unbounded, walking through a region's worth of houses retains a few
-- dozen of them; the audit run that first exercised this was killed by the
-- kernel after a hundred and fifty maps. The player only ever needs the map
-- they are on and its neighbours, so keep a handful and release the rest.
local MAP_SHAPE_KEEP = 6
local mapShapeCache = {}
local mapSolidCache = {}
local mapShapeOrder = {}

local function rememberMapShape(key, surface, frac)
  mapShapeCache[key] = surface
  mapSolidCache[key] = frac
  for i = #mapShapeOrder, 1, -1 do
    if mapShapeOrder[i] == key then table.remove(mapShapeOrder, i) end
  end
  mapShapeOrder[#mapShapeOrder + 1] = key
  while #mapShapeOrder > MAP_SHAPE_KEEP do
    local old = table.remove(mapShapeOrder, 1)
    local dead = mapShapeCache[old]
    mapShapeCache[old] = nil
    mapSolidCache[old] = nil
    if type(dead) == "table" and type(dead.release) == "function" then
      pcall(dead.release, dead)
    end
  end
end
function Gen3.shapeDataForMap(map)
  local ctx = Gen3.forMap(map)
  if not ctx then return nil end
  local tileset = ctx.tileset
  if not Gen3.isGen3(tileset) then return nil end
  local floors = ctx.floorMetatiles
  if not floors or #floors == 0 then
    return Gen3.shapeDataForTileset(tileset)
  end
  local key = tostring(tileset.id) .. "|" .. (ctx.floorKey or "")
  local hit = mapShapeCache[key]
  if hit ~= nil then return hit or nil end
  mapShapeCache[key] = false

  local art = analyse(tileset)
  local tiles = art and tilesForTileset(tileset)
  if not (art and tiles) then return Gen3.shapeDataForTileset(tileset) end
  if not (love and love.image and love.image.newImageData) then return nil end

  -- the pair's background, widened by this map's floor colours
  local background = {}
  for c in pairs(art.background) do background[c] = true end
  local floorSet = {}
  for _, m in ipairs(floors) do floorSet[m] = true end
  local floorHist, floorTotal = {}, 0
  pcall(tiles.bakeLayer, tiles, 1, function(x, y, r, g, b)
    local m = math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
    if floorSet[m] then
      local c = colourKey(r, g, b)
      floorHist[c] = (floorHist[c] or 0) + 1
      floorTotal = floorTotal + 1
    end
  end)
  -- a floor colour that object art leans on is not background (the same
  -- guard the pair-level set uses)
  local objectHist = {}
  pcall(tiles.bakeLayer, tiles, 2, function(x, y, r, g, b)
    local c = colourKey(r, g, b)
    objectHist[c] = (objectHist[c] or 0) + 1
  end)
  for c, n in pairs(floorHist) do
    if n >= floorTotal * 0.002 and (objectHist[c] or 0) < n * 0.5 then
      background[c] = true
    end
  end

  local info = Gen3.describe(tileset)
  local W, H = info.width, info.height
  -- how much of each cell survives THIS map's carve: the number the indoor
  -- classifier reads, because a table is only distinguishable from a wall by
  -- the floor showing around it
  local solid = {}
  local okBake, res = pcall(function()
    local surface = love.image.newImageData(W, H)
    local function place(x, y)
      local m = math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
      local q = math.floor((y % CELL) / TILE) * 2 + math.floor((x % CELL) / TILE)
      local t = m * 4 + q
      return (t % LINEAR_COLS) * TILE + (x % TILE),
             math.floor(t / LINEAR_COLS) * TILE + (y % TILE)
    end
    tiles:bakeLayer(1, function(x, y, r, g, b)
      local dx, dy = place(x, y)
      if dx < 0 or dy < 0 or dx >= W or dy >= H then return end
      if background[colourKey(r, g, b)] then
        surface:setPixel(dx, dy, 0, 0, 0, 0)
      else
        surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
        local m = math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
        solid[m] = (solid[m] or 0) + 1
      end
    end)
    tiles:bakeLayer(2, function(x, y, r, g, b)
      local dx, dy = place(x, y)
      if dx < 0 or dy < 0 or dx >= W or dy >= H then return end
      surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
      local m = math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
      solid[m] = (solid[m] or 0) + 1
    end)
    return surface
  end)
  if not (okBake and res) then
    return Gen3.shapeDataForTileset(tileset)
  end
  local frac = {}
  for m, n in pairs(solid) do
    local f = n / 256
    frac[m] = f > 1 and 1 or f
  end
  rememberMapShape(key, res, frac)
  say("mapshape", "carved %s for its own floor -- %d floor metatile(s)",
      tostring(tileset.id), #floors)
  return res
end

--- How much of a metatile survives THIS map's carve, 0..1. Nil when the map
--- has no carve of its own.
function Gen3.solidForMap(map, metatile)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.floorKey and ctx.floorKey ~= "") then return nil end
  local key = tostring(ctx.tileset.id) .. "|" .. ctx.floorKey
  if mapSolidCache[key] == nil then Gen3.shapeDataForMap(map) end
  local t = mapSolidCache[key]
  return t and t[tonumber(metatile) or -1] or nil
end

function Gen3.shapeData(map)
  local ctx = Gen3.forMap(map)
  if not ctx then return nil end
  return Gen3.shapeDataForTileset(ctx.tileset)
end

-- ---------------------------------------------------------------------------
-- THE ANIMATED TILES, AS PATCHES INTO THE RELAID SHEET.
--
-- THE SEA SOUTH OF ROUTE 104 AND THE FLOWER BEDS IN ITS FIELDS.  In the flat
-- game those move; in the diorama they were a photograph, because this file
-- bakes a pair's art ONCE, caches it by tileset id, and the mesh samples that
-- one texture forever.  The mesh is not the problem and never was -- the
-- geometry of a pond does not change shape when the water moves -- so this
-- does what `TerrainAtlas` already does for Johto's surf shimmer: keep a
-- private copy of the sheet and rewrite the moving slots in it when the step
-- turns over.  No mesh is rebuilt, no UV moves, and SHAPE_REV is untouched.
--
-- WHAT A GEN 3 ANIMATED TILE IS, AND WHY IT IS NOT A SLOT.
--
-- Gen 1 and Gen 2 animate an ATLAS CELL: water is tile $14, and rewriting
-- that one 8x8 slot moves every pond in the region.  Emerald animates a RUN OF
-- TILE GRAPHICS -- 30 tiles at index 432 for the sea and its shore, 2 at 508
-- for the flowers -- and a single one of those tiles is referenced by 148 of
-- the 862 metatiles in the Route 104 pair.  In this file's relaid layout,
-- metatile `m` quadrant `q` is synthetic tile `4m + q`, so ONE animated
-- cartridge tile becomes several hundred slots in the sheet.
--
-- So the patch is precomputed as STRIPS: one ImageData per step, holding the
-- new 8x8 for every slot that moves, laid side by side.  Applying a step is
-- then `#slots` calls to ImageData:paste -- a memcpy per row inside LOVE --
-- rather than tens of thousands of setPixel calls three times a second.
--
-- A quadrant is included when EITHER of its two layer entries names an
-- animated tile, because the relaid sheet writes layer 1 and then layer 2 into
-- the same slot (bakeLinear does exactly that) and either can be the thing
-- that moves.
-- ---------------------------------------------------------------------------

local animPatchCache = {}

function Gen3.animPatchesForTileset(tileset)
  if not Gen3.isGen3(tileset) then return nil end
  local key = tostring(tileset.id)
  local hit = animPatchCache[key]
  if hit ~= nil then return hit or nil end
  animPatchCache[key] = false

  local tiles = tilesForTileset(tileset)
  if not tiles then return nil end
  -- an engine that predates g3-anim-261 has no animation model at all; that
  -- is not a failure, it is a host without the data, and the world keeps its
  -- static sheet
  if type(tiles.animSteps) ~= "function" then return nil end

  local okBuild, res = pcall(function()
    local steps = tiles:animSteps()
    if not steps or steps < 2 then return nil end
    local animTiles = tiles:animTileMap()
    local cells = tiles:animMetatiles()
    if not (animTiles and cells) then return nil end
    if not (love and love.image and love.image.newImageData) then return nil end

    -- WHICH SLOTS MOVE.  Walked in metatile order so the strip layout is
    -- deterministic -- two runs of the same tileset must produce the same
    -- strips, or a cached mesh and a fresh one would sample different pixels.
    local slots, owner = {}, {}
    local ordered = {}
    for m in pairs(cells) do ordered[#ordered + 1] = m end
    table.sort(ordered)
    for _, m in ipairs(ordered) do
      local entries = tiles:entries(m)
      for q = 0, 3 do
        local bottom, top = entries[q + 1], entries[q + 5]
        if (bottom and animTiles[bottom.tile])
           or (top and animTiles[top.tile]) then
          slots[#slots + 1] = m * 4 + q
          owner[#slots] = m
        end
      end
    end
    if #slots == 0 then return nil end

    local strips = {}
    for step = 0, steps - 1 do
      local strip = love.image.newImageData(#slots * 8, 8)
      -- one metatile is rendered once per step and read four times at most,
      -- so compose it whole and cut quadrants out of it
      local cellBuf = love.image.newImageData(CELL, CELL)
      local lastM = nil
      local function compose(m)
        if lastM == m then return end
        lastM = m
        for y = 0, CELL - 1 do
          for x = 0, CELL - 1 do cellBuf:setPixel(x, y, 0, 0, 0, 0) end
        end
        local function plot(x, y, r, g, b)
          if x >= 0 and y >= 0 and x < CELL and y < CELL then
            cellBuf:setPixel(x, y, r / 255, g / 255, b / 255, 1)
          end
        end
        -- bottom then top, the order bakeLinear composites them in, so the
        -- patched slot is what a fresh bake at this step would have produced
        tiles:drawLayer(m, 1, 0, 0, plot, step)
        tiles:drawLayer(m, 2, 0, 0, plot, step)
      end
      for i, t in ipairs(slots) do
        local m, qd = owner[i], t % 4
        compose(m)
        local sx, sy = (qd % 2) * TILE, math.floor(qd / 2) * TILE
        strip:paste(cellBuf, (i - 1) * 8, 0, sx, sy, TILE, TILE)
      end
      strips[step + 1] = strip
    end
    return { steps = steps, period = tiles:animPeriod() or 16,
             slots = slots, strips = strips }
  end)

  if not (okBuild and res) then
    if not okBuild then
      warn("animfail", "building the %s animation patches failed: %s", key,
           tostring(res))
    end
    return nil
  end
  animPatchCache[key] = res
  say("anim", "%s animates %d slot(s) over %d step(s), one every %d frame(s)",
      key, #res.slots, res.steps, res.period)
  return res
end

function Gen3.animPatches(map)
  local ctx = Gen3.forMap(map)
  if not ctx then return nil end
  return Gen3.animPatchesForTileset(ctx.tileset)
end

function Gen3.atlas(map)
  local ctx = Gen3.forMap(map)
  if not ctx then return nil end
  return Gen3.atlasForTileset(ctx.tileset)
end

function Gen3.atlasData(map)
  local ctx = Gen3.forMap(map)
  if not ctx then return nil end
  return Gen3.atlasDataForTileset(ctx.tileset)
end

function Gen3.releaseAtlases()
  atlasCache = {}
  atlasDataCache = {}
  animPatchCache = {}
  atlasInfoCache = {}
  shapeCache = {}
  mapShapeCache = {}
  mapSolidCache = {}
  mapShapeOrder = {}
  artCache = {}
end

function Gen3.invalidate()
  ctxCache = setmetatable({}, { __mode = "k" })
  ctxMisses = setmetatable({}, { __mode = "k" })
  atlasCache = {}
  atlasDataCache = {}
  atlasInfoCache = {}
  shapeCache = {}
  mapShapeCache = {}
  mapSolidCache = {}
  mapShapeOrder = {}
  artCache = {}
  reported = {}
end


-- ---------------------------------------------------------------------------
-- THE ROLE VOCABULARY, at module level.
--
-- Every Gen 3 terrain pass should ask these rather than re-deriving what a
-- cell is from art or from collision alone.  Both are cheap: roleAt memoises
-- per cell on the map's context and buildings() builds once per map.
-- ---------------------------------------------------------------------------

--- floor / stair / water / ledge / cliff / wall / tree / prop, or nil off-map.
function Gen3.roleAt(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.roleAt) then return nil end
  local ok, r = pcall(ctx.roleAt, cx, cy)
  return ok and r or nil
end

--- TRUE ON A CELL THE HEIGHT FIELD READ AS A DRAWN FACE rather than as
--- ground -- a transition chain climbing more than one course with no tread
--- drawn in it.  Fortree's five ladders are the whole population in Hoenn.
function Gen3.faceRampAt(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.faceRampAt) then return false end
  local ok, r = pcall(ctx.faceRampAt, cx, cy)
  return (ok and r) == true
end

--- art, material, cap, face, kind, motif for one metatile, or nil.
function Gen3.metaRole(map, metatile)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metaRole) then return nil end
  local ok, a, b, c, d, e, f = pcall(ctx.metaRole, metatile)
  if not ok then return nil end
  return a, b, c, d, e, f
end

--- HOW MANY COURSES OF CLIFF THIS ONE CELL DRAWS: 1 or 0.
---
--- Two things in Emerald's art are each worth a course, and they look nothing
--- alike:
---
---   a LEDGE -- a hard shadow line with masonry above and below it.  That is
---   how Sootopolis draws a worked stone step (577), and the raised body
---   behind it (737) has no such line and is worth nothing.
---
---   a FRONT FACE -- a cell that is nothing BUT the vertical face, which is
---   how the crater's rust wall and Mt Chimney's ash banks are drawn.  There
---   is no shadow line because there is no top edge in the cell at all.
---
--- Counting these up a run is what makes a cliff drawn three faces tall come
--- out three courses tall.
-- A WALL IS NEVER WALKABLE ANYWHERE.
--
-- Sootopolis' pale stone pavement is metatile 729, and the tileset draws it
-- with a lit top edge and a shadow -- which is exactly how it draws a terrace
-- rim, so `metaRole` calls it `brow` and every reader downstream calls it a
-- step.  It covers 894 cells, a quarter of the map, and charged as a step it
-- raises a block wherever it lies: the quilt of little walls around every
-- house in the frame, and the maze of white rock the city renders as.  It is
-- also, at a glance at the 2D art, plainly the ground the town is paved with.
--
-- The cartridge already says which it is, and says it in the one place that
-- cannot be drawn: 607 of those 894 cells ARE WALKABLE.  You cannot stand on
-- the front of a cliff.  A metatile you can stand on in most of the places it
-- appears is ground, and the places it is blocked are blocked by something
-- standing ON it -- a fence, a signpost, a planter -- not because the stone
-- became a wall there.
--
-- Measured across the region, the two populations do not overlap:
--
--     map                metatile   cells   walkable
--     SootopolisCity          729     894        67%   pavement
--     MtChimney               625     636        53%   ash floor
--     Route112                625     268        50%   ash floor
--     RustboroCity            545      16       100%   paving
--     SootopolisCity          113     161        48%   south rim
--     Route116                113     452        14%   rock
--     MtPyre_Exterior         113     270         5%   rock
--     SootopolisCity          737     299         0%   crater wall
--     SootopolisCity          730     126         0%   crater wall
--
-- Every real wall is at or under 14%; every misread ground is at or over 48%.
-- A simple majority sits in the gap with room on both sides, and it is the
-- rule with a reason behind it rather than a threshold picked to fit.
--
-- Deliberately NOT flattened: Sootopolis' southern rim, which the art draws as
-- 617 -> 113 -> 748 -> 721, one metatile per row of terrace.  113 is 48%
-- walkable and stays an edge, which is what keeps those rows stepping -- the
-- fault that counting brows was added to fix.
--
-- In-game location: Sootopolis City, the stone the whole town is paved with,
-- and the same reading leaves its southern rim (rows y=56..59) stepping.
local groundMetaCache = setmetatable({}, { __mode = "k" })
local function groundMetaFor(map, ctx)
  if not (ctx and ctx.metatileAt and ctx.metaRole) then return nil end
  local hit = groundMetaCache[ctx]
  if hit then return hit end
  local set = {}
  groundMetaCache[ctx] = set          -- publish first: the scan below must not
                                      -- re-enter this function for every cell
  local def = map and map.def
  local W = math.floor(tonumber(def and def.width) or 0)
  local H = math.floor(tonumber(def and def.height) or 0)
  if W < 1 or H < 1 then return set end
  local total, walk = {}, {}
  for cy = 0, H - 1 do
    for cx = 0, W - 1 do
      local okM, m = pcall(ctx.metatileAt, cx, cy)
      if okM and m then
        -- only ART cells are in question: a metatile nobody calls an edge is
        -- not being mistaken for one
        local okR, art, _, _, face = pcall(ctx.metaRole, m)
        if okR and (art == "brow" or (tonumber(face) or 0) >= 12) then
          total[m] = (total[m] or 0) + 1
          local okW, w = pcall(map.isWalkableCell, map, cx, cy)
          if okW and w then walk[m] = (walk[m] or 0) + 1 end
        end
      end
    end
  end
  for m, n in pairs(total) do
    if (walk[m] or 0) * 2 > n then set[m] = true end
  end
  return set
end

-- Is this cell's metatile one the map is PAVED with?
function Gen3.isGroundMeta(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt) then return false end
  local set = groundMetaFor(map, ctx)
  if not set then return false end
  local okM, m = pcall(ctx.metatileAt, cx, cy)
  if not okM or not m then return false end
  return set[m] == true
end

--- Is the cell here drawn from a tileset that states no vertical structure
--- anywhere -- no drawn top edge and no drawn face on any of its rows?
---
--- (Hoenn's twelve dive maps, gTileset_Underwater.  See
--- `ctx.ownerStatesNoRelief` for the whole-table measurement.)  A dive map
--- places metatiles from its SECONDARY only -- 0 primary cells on all twelve,
--- measured -- so this is a property of the cell's own drawing, asked per
--- cell rather than per map so that a mass which reaches into face-drawing
--- art is not covered by it.
function Gen3.statesNoReliefAt(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt and ctx.ownerStatesNoRelief) then return false end
  local okM, m = pcall(ctx.metatileAt, cx, cy)
  if not okM or not m then return false end
  local owner = (m < 512) and ctx.ownerPrimary or ctx.ownerSecondary
  return ctx.ownerStatesNoRelief(owner) == true
end

function Gen3.courseAt(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt and ctx.metaRole) then return 0 end
  local okM, m = pcall(ctx.metatileAt, cx, cy)
  if not okM or not m then return 0 end
  local okR, art, _, _, face, _, _, _, _, ledge = pcall(ctx.metaRole, m)
  if not okR then return 0 end
  -- a ledge is the map's own signed statement and outranks the art reading
  if ledge then return 1 end
  -- ...and paving is not a course, however the tileset shades it
  local ground = groundMetaFor(map, ctx)
  if ground and ground[m] then return 0 end
  -- COVERAGE, NOT THE ART LABEL.
  --
  -- This asked for `art == "face"`, and Sootopolis' crater wall is not labelled
  -- that: metatile 737 is `banded` art with face coverage 15 of 16, and 723
  -- and 724 are `brow` with 6.  So the deepest wall in Hoenn scored zero
  -- courses and the town's relief had to be guessed from its lake instead.
  -- The consequence was measured when terraces were merged across boundaries
  -- the reader scored 0: Sootopolis' flat flights went from 3 of 24 to 11 and
  -- its cliffs separating nothing from 266 to 588, because real walls were
  -- being merged away.
  --
  -- What makes a cell one course is that the tileset paints it as a vertical
  -- face, and that is what the coverage measures.  The label is about how the
  -- face is drawn -- banded, browed, plain -- not whether it is one.  Twelve
  -- of sixteen keeps the threshold where it was: a cell more than three
  -- quarters face is a course of face, a cell that is mostly top surface is
  -- not, and a body cell with no face at all is still worth nothing however
  -- many of them are stacked.
  -- A CORNER IS STILL A FACE.
  --
  -- Coverage is measured across the cell, so where a cliff TURNS -- the face
  -- on one side only -- it reads 0 and the corner scored no course.  Sootopolis
  -- shows it plainly: the Mart's terrace is ringed by `face` art with coverage
  -- 0 at every corner (16,28) (17,28) (18,28), and with the corners uncounted
  -- the boundary round that terrace summed to nothing and the whole shelf sat
  -- flat.  The southern rim is the same fault at scale -- its steps turn
  -- constantly.
  --
  -- The label is the evidence here, not the coverage: a metatile the tileset
  -- calls a FACE is a face however little of the cell it fills.  `banded` still
  -- needs the coverage test, because a staircase's treads are banded and must
  -- not be counted twice -- once as treads and once as faces.
  if art == "face" then return 1 end
  if (tonumber(face) or 0) >= 12 then return 1 end
  -- AND A BROW IS A COURSE, EVEN WITH NO FACE DRAWN ON IT.
  --
  -- Hoenn draws cliffs two ways and Sootopolis uses both: the brown rim around
  -- the lake, which is a front face you can count pixels of, and the ash-white
  -- town terraces, which are drawn as a RIM -- a lit top edge with a shadow
  -- under it and no face below, because the next terrace starts immediately.
  -- The southern half of Sootopolis is all of the second kind: metatiles 720,
  -- 721, 728, 729, 731 and 748 are `brow` art with face coverage of 1 to 7,
  -- and counting only coverage scored every one of them zero.  Eight rows of
  -- drawn terracing came out flat at the datum.
  --
  -- A brow IS a step: it is the top edge of one, which is the whole of what
  -- the tileset draws where two terraces meet without room for a face between
  -- them.  `art` distinguishes it from the body of a mass -- `surface` -- so
  -- counting it does not re-open the skyline that counting every cliff cell
  -- once produced.
  if art == "brow" then return 1 end
  return 0
end

--- Which KIND of cliff this cell draws: a front face (one metatile per course)
--- or a brow (the top edge of a single step, which Hoenn draws two and three
--- cells deep).  They have to be counted differently -- see the outward course
--- climb in Structures.
--- The metatile drawn at a cell, or nil.  A band of brow is one step however
--- deep it is drawn, and what tells one band from the next is that the tileset
--- changes metatile: Sootopolis' southern rim runs 748, 721, 729, 720, 728,
--- 731 going outward, each a different row of the same white stone.
function Gen3.metatileNumAt(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt) then return nil end
  local ok, m = pcall(ctx.metatileAt, cx, cy)
  if not ok then return nil end
  return m
end

function Gen3.faceKindAt(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt and ctx.metaRole) then return false, false end
  local okM, m = pcall(ctx.metatileAt, cx, cy)
  if not okM or not m then return false, false end
  local okR, art, _, cap, face = pcall(ctx.metaRole, m)
  if not okR then return false, false end
  -- the same reading `courseAt` uses, so the band raster and the drawing can
  -- never disagree about what is an edge
  local ground = groundMetaFor(map, ctx)
  if ground and ground[m] then return false, false end
  -- A BROW IS A DRAWN TOP AND THEN A FACE.  WITH NO TOP IT IS A FACE.
  --
  -- MOTIVATED BY THE CELLS FLANKING EVERY FORTREE HUT DOOR.
  --
  -- The role table's own definition: "brow -- surface rows and then face
  -- rows: `cap` is the row it turns over at and `face` is how many rows of
  -- wall follow".  `cap == 0` is no surface rows at all, which is the same
  -- statement `art = "face"` makes; the generator writes "brow" for those
  -- rows only because it also read a `facing` off them.
  --
  -- `capGen3Rock`'s "A FRONT FACE IS NOT A BANK" demotes a pure face flush
  -- with the ground it fronts and keeps a brow standing a course, and this
  -- was the only thing separating Fortree's two door-jamb metatiles: 564
  -- (west) is "brow"/rock/cap 0/face 12 and 566 (east) is "face"/rock/cap 0/
  -- face 16, the same drawing mirrored.  So 566 came up flush with the plank
  -- platform at 32 and 564 stood at 48 -- a sixteen-pixel block on one side
  -- of every hut door and nothing on the other, on nine of the twelve jambs
  -- in the town.
  return (tonumber(face) or 0) >= 12,
         art == "brow" and (tonumber(cap) or 0) > 0
end

-- WHICH WAY A LEDGE DROPS, WHICH IS THE ONLY SIGNED HEIGHT STATEMENT EMERALD
-- MAKES.
--
-- MB_JUMP_SOUTH means: the ground NORTH of this cell stands one course above
-- the ground SOUTH of it, you may hop that way, and you may not hop back.
-- Eight directions, 760 cells over 22 outdoor maps -- and unlike
-- MB_MOUNTAIN_TOP it names the size of the step AND which way it faces.
--
-- Everything else the height model has is unsigned: a boundary weight caps a
-- step without saying which side is up, a staircase's tread count is a size
-- with the direction guessed from distance to water.  This is the one input
-- that needs no guess, and until now nothing read it: measured over the
-- region, 14% of ledges step correctly, 71% are flat and 9% are INVERTED --
-- the ground you hop down to is drawn higher than the ground you leave.
--
-- Returns dx, dy pointing at the LOW side (the way you hop), or nil.
local LEDGE_HOP = {
  [0x38] = {  1,  0 },   -- MB_JUMP_EAST
  [0x39] = { -1,  0 },   -- MB_JUMP_WEST
  [0x3A] = {  0, -1 },   -- MB_JUMP_NORTH
  [0x3B] = {  0,  1 },   -- MB_JUMP_SOUTH
  [0x3C] = {  1, -1 },   -- MB_JUMP_NORTHEAST
  [0x3D] = { -1, -1 },   -- MB_JUMP_NORTHWEST
  [0x3E] = {  1,  1 },   -- MB_JUMP_SOUTHEAST
  [0x3F] = { -1,  1 },   -- MB_JUMP_SOUTHWEST
}

function Gen3.ledgeHopAt(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt and ctx.attributes) then return nil end
  local okM, m = pcall(ctx.metatileAt, cx, cy)
  if not okM or not m then return nil end
  local okA, b = pcall(ctx.attributes, m)
  if not okA then return nil end
  local d = LEDGE_HOP[b]
  if not d then return nil end
  return d[1], d[2]
end

--- How many ledges this map states.  The gate for running the height pass on
--- a map with no lake: a route with fifty stated drops has more to say about
--- its own relief than the elevation grid does.
function Gen3.ledgeCount(map)
  local W = math.floor(tonumber(map.def and map.def.width) or 0)
  local H = math.floor(tonumber(map.def and map.def.height) or 0)
  if W < 1 or H < 1 then return 0 end
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt and ctx.attributes) then return 0 end
  if ctx.ledgeN ~= nil then return ctx.ledgeN end
  local n = 0
  for cy = 0, H - 1 do
    for cx = 0, W - 1 do
      local okM, m = pcall(ctx.metatileAt, cx, cy)
      if okM and m then
        local okA, b = pcall(ctx.attributes, m)
        if okA and LEDGE_HOP[b] then n = n + 1 end
      end
    end
  end
  ctx.ledgeN = n
  return n
end

--- WHICH SIDE OF A CLIFF IS THE HIGHER GROUND: "N" when the high side is
--- north of this cell, "S" when it is south, nil when the art does not say.
---
--- Read from the drawing: a terrace over a wall means you are looking at the
--- cliff from the south and the high ground is behind it; a wall over a
--- terrace is the reverse.  A pure face has no answer of its own -- ask the
--- brow that caps the run.
function Gen3.cliffFacing(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt and ctx.metaRole) then return nil end
  local okM, m = pcall(ctx.metatileAt, cx, cy)
  if not okM or not m then return nil end
  local okR, _, _, _, _, _, _, _, facing = pcall(ctx.metaRole, m)
  if not okR then return nil end
  -- "S" on the row means the drawing is south-facing, so the HIGH side is
  -- north.  Answer in terms of where the high ground is, which is what every
  -- caller actually wants.
  if facing == "S" then return "N" end
  if facing == "N" then return "S" end
  return nil
end

--- WHICH WAY A TREAD CLIMBS: "y" north-south, "x" east-west, nil if not a
--- tread or if the tileset is one the role table has never seen.
---
--- The art states this and it is not a close call -- a staircase's row
--- luminances repeat exactly while its columns stay flat, or the reverse --
--- so a flight never has to guess its direction from the terrain either side.
--- Guessing is what turned Sootopolis' north-south steps into east-west ones.
function Gen3.stairAxis(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metatileAt and ctx.metaRole) then return nil end
  local okM, m = pcall(ctx.metatileAt, cx, cy)
  if not okM or not m then return nil end
  local okR, art, _, _, _, _, _, axis = pcall(ctx.metaRole, m)
  if not okR or art ~= "banded" then return nil end
  if axis == "x" or axis == "y" then return axis end
  return nil
end

--- { list = { {cells={{x,y}..}, door={x,y}} .. }, cell = { [y*8192+x] = i } }
function Gen3.buildingsOf(map)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.buildings) then return nil end
  local ok, b = pcall(ctx.buildings)
  return ok and b or nil
end

--- Is this cell part of a building the cartridge put a door on?
function Gen3.isBuildingCell(map, cx, cy)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.isBuildingCell) then return false end
  local ok, r = pcall(ctx.isBuildingCell, cx, cy)
  return (ok and r) or false
end

return Gen3
