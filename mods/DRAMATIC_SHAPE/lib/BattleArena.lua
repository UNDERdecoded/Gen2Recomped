-- Overworld battles: where the fight is staged.
--
-- A battle in this mod happens ON THE MAP, so it needs a patch of ground
-- clear enough to stand two Pokemon on and point a camera down. This module
-- finds it: the nearest patch of open cells, in the shape below.
--
--     x x x
--     x O x        O   the enemy's mon
--     x x x
--     x x x
--     x P x        P   the player's mon
--     x x x
--
-- Every `x` is an OPEN cell -- one with no obstruction, i.e. one the player
-- could walk onto. The two mons stand three cells apart down the middle
-- column, with a one-cell apron all round so the camera looks across floor
-- rather than into a wall.
--
-- When no map has room for that -- a corridor, a cave, a shop floor -- the
-- search relaxes to the narrow shape, which is the same three-cell gap with
-- the apron given up:
--
--     O
--     x
--     x
--     P
--
-- and if even that will not fit, the caller gets nil and the battle draws
-- the way it always did. A mod that cannot find a stage does not invent
-- one.
--
-- Nothing here MOVES anybody: the arena is where the CAMERA goes and where
-- the two mons are staged for the shot. The player's own cell, the party,
-- every script and flag are exactly where the battle left them, which is
-- what keeps a trainer's post-battle dialogue talking to someone still
-- standing in front of them.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleArena = {}

-- ------- the authored spot
--
-- Every map gets ONE place its battles happen, chosen once and written down
-- in data/battle_arenas.lua, rather than whatever clearing happens to be
-- nearest to wherever the fight started. Two reasons.
--
-- A fight should look the same every time it happens somewhere. Picking the
-- nearest patch means Route 1 has a dozen different battle scenes depending
-- on which step of the grass you were on, some of them behind a tree.
--
-- And "open ground" is not the same question as "you can SEE the two of
-- them". The camera is low and a long way back, so a hedge, a ledge lip or a
-- building corner anywhere along that line hides a mon completely while the
-- cells it stands on are perfectly walkable. That is what `clearance` below
-- measures, and it is what the authored list is chosen against.
--
-- A map with no entry falls back to the search, so a mod that adds maps, or
-- an entry that goes stale, degrades to the old behaviour rather than to no
-- battle.
-- An entry may also name ANOTHER MAP to stage on:
--
--   ["MT_MOON_B2F"] = { map = "MT_MOON_1F", x = 12, y = 8, shape = "wide" }
--
-- because some maps simply have nowhere to put a fight. A cave's lower floor
-- can be nothing but two-cell-wide corridors between rock walls; a gym is a
-- room full of furniture. Rather than stage a battle there badly -- both
-- Pokemon behind a boulder -- the fight is shot on a floor of the SAME cave,
-- or a floor of the same building, that does have the room for it. It is the
-- same place, and no worse a fiction than a battle happening on ground the
-- player is not standing on, which is what every one of these already is.
local authored = nil
local overrides = {}

local function authoredFor(mapId)
  -- `~= nil`, not truthiness: `false` is a meaningful entry here (an
  -- authored refusal), so it has to reach the caller rather than read as
  -- "nothing set" and fall through to the data file
  local forced = overrides[mapId]
  if forced ~= nil then return forced end
  if authored == nil then
    local ok, list = pcall(V.data, "battle_arenas")
    authored = (ok and type(list) == "table") and list or false
  end
  if not authored then return nil end
  return authored[mapId]
end

BattleArena.authoredFor = authoredFor

-- Force one map's entry at runtime, ahead of the data file. The authoring
-- tool's handle: it is how a spot chosen by eye is staged and photographed
-- before it is written down, and the only way to check a cross-floor entry
-- without editing the shipped list first. Pass nil to drop it again.
function BattleArena.setOverride(mapId, entry)
  overrides[mapId] = entry
end

-- Cell size in world pixels, the unit every coordinate here is in when it
-- crosses into the renderer (Map's walk grid is 16px cells).
local CELL = 16

-- The two shapes, in preference order. `w`/`h` are in cells; `enemy` and
-- `player` are the offsets, from the shape's north-west corner, of the two
-- cells a mon stands on.
BattleArena.SHAPES = {
  { id = "wide",   w = 3, h = 6, enemy = { 1, 1 }, player = { 1, 4 } },
  { id = "narrow", w = 1, h = 4, enemy = { 0, 0 }, player = { 0, 3 } },
}

-- Whether a cell is open ground for the purpose above.
--
-- "Open" is the walk test the player themselves answer to, so an arena can
-- never be laid over a wall, a counter, a tree or a ledge face. Water counts
-- only for a surfer, which is the one case where the player is standing on
-- it too -- a sea battle staged on the beach half a route away would read as
-- a teleport.
--
-- Warp cells are excluded on top of that. They are walkable by definition
-- (they are the doormat), and a fight framed in a doorway both looks wrong
-- and puts the camera inside the building's geometry.
--
-- And TALL GRASS is excluded, which is the surprising one, because grass is
-- where wild battles come from and standing in it is the obvious place to
-- have one. It does not survive contact with the camera. Grass is real
-- geometry in this mode -- a row of tufts about knee height on a Pokemon --
-- drawn with the same camera-ward bias that lets it overdraw a walking
-- character's feet in the free-roam world. From a camera nearly level with
-- the floor that bias stops being feet-deep: the tufts on and around a mon's
-- own tile stand between it and the lens and eat most of the sprite.
--
-- So the arena is laid on bare ground -- the whole footprint, not just the
-- two cells a mon stands on, because the apron south of the near mon is
-- exactly the row whose grass would cover it. Grass FURTHER back toward the
-- camera is fine and stays: it is far enough forward to project low and wide
-- across the bottom of the frame, where it reads as a field rather than as
-- something in the way.

-- ...AND ON THIS CARTRIDGE `isWalkableCell` SAYS THE SEA IS OPEN GROUND.
--
-- In-game location: the bay on Route 103, the river Route 118 crosses, and
-- the pond at the south end of Route 111 -- which was the arena for a fight
-- started anywhere on that route, a hundred cells away in the desert.
--
-- Emerald does not block the ocean with collision.  Route 129 is eighty
-- cells square of behaviour 0x15 with collision 0 -- perfectly passable as
-- far as the collision bits are concerned -- and what keeps a walking
-- trainer out of it is the OTHER half of the map word: water is elevation 1
-- and land is elevation 3, and the cartridge refuses a step between two
-- different non-zero elevations (`Map:cellElevation` says so in as many
-- words).  `Map:isWalkableCell` reads only the collision bits, so it answers
-- true on every sea cell in Hoenn and the surfing gate three lines below it
-- -- written for Gen 1 and Gen 2, where water IS collision -- never got to
-- decide anything.  A walker who met a Poochyena on the Route 103 beach had
-- the fight staged eight cells out to sea, both cards standing on the surf.
--
-- The honest question is what the cartridge says the cell IS, and
-- `Gen3.roleAt` already answers it off the elevation grid and the behaviour
-- byte together -- which is what makes it right about the two things a plain
-- byte test gets wrong: Route 110's cycling road is 46 cells of elevation 1
-- that are a BRIDGE, and Sootopolis' blue-painted Mart roof is not a lake.
-- Gen 1 and Gen 2 have no such role and fall back to the tile test they
-- always used, where water was never walkable in the first place, so nothing
-- about them moves.
--
-- Measured over the 81 outdoor Hoenn maps, 1,565 sampled battles: 182 of
-- them (11.6%), on 35 maps, stood at least one card on water while the
-- player was on land.  Rustboro's every battle was staged on the sea at the
-- map's own west edge, 24 cells from the player.
local function waterCell(map, cx, cy)
  local okR, role = pcall(V.require("Gen3").roleAt, map, cx, cy)
  if okR and role ~= nil then
    return role == "water" or role == "waterfall"
  end
  -- NO on anything that is not a Gen 3 map, deliberately.  `Gen3.roleAt`
  -- answers nil for Gen 1, Gen 2 and Prism (`Gen3.forMap` returns before it
  -- builds anything), and on those profiles water is not in the tileset's
  -- walkable set in the first place -- the surfing branch below has always
  -- been the only way onto it.  Answering `map:isWaterCell` here instead
  -- would be a second, differently-derived veto on maps that never needed
  -- one, so those three profiles come out of this bit-identical.
  return false
end

-- ...AND THE GRASS RULE ABOVE IS INERT IN HOENN, WHICH IS CORRECT.
--
-- Worth writing down, because it looks like a bug and is not.  On a Gen 3
-- map `Map:isGrassCell` is always false -- it tests `grassTiles[cellTile]`,
-- and `grassTiles` is empty for every Gen 3 tileset pair while `cellTile`
-- answers a behaviour byte rather than a tile id -- so the no-grass rule
-- never rejects a cell in Hoenn.  The first instinct is to replace it with
-- the cartridge's own behaviour byte (0x02 MB_TALL_GRASS, 0x03 MB_LONG_GRASS,
-- 0x24 MB_ASHGRASS on Route 113): that was written, measured, and thrown
-- away.
--
-- `Structures.buildGrass` sprouts a tuft only where the tile's art is grass
-- AND `map:isGrassCell` agrees -- the SAME test -- so Hoenn draws no tufts
-- at all: `S.grassQuads` is 0 on Route 101, 113, 119, 104 and Petalburg
-- alike (and `S.flowerQuads` with it).  Hoenn's tall grass is a flat texture
-- on flat ground, and flat ground hides nothing.  The rule and the geometry
-- are gated on one test, so the rule is exactly as true as the tufts are.
--
-- Rejecting grass anyway costs real distance for nothing: it moved Route
-- 113's arena from 3.4 cells away to 38.6, and Route 121's from 6.9 to 39.5,
-- to avoid something that is not drawn.  Left as it stands, so that a
-- profile which DOES draw grass -- Kanto and Johto do -- still gets the rule
-- it was written for.

local function openCell(map, cx, cy, surfing)
  if not map:inBounds(cx, cy) then return false end
  if map:warpAtCell(cx, cy) then return false end
  if map:isWarpTileCell(cx, cy) then return false end
  if map.isGrassCell and map:isGrassCell(cx, cy) then return false end
  -- water is ground for whoever is standing on it and for nobody else
  if waterCell(map, cx, cy) then return (surfing and true) or false end
  if map:isWalkableCell(cx, cy) then return true end
  return (surfing and map:isWaterCell(cx, cy)) or false
end

BattleArena.openCell = openCell

-- The map's open cells as one flat boolean grid, so the rectangle test
-- below is a lookup rather than a tileset walk per cell. Built once per
-- search; a battle asks for one.
local function openGrid(map, surfing)
  local w, h = map.widthCells, map.heightCells
  local grid = {}
  for cy = 0, h - 1 do
    local row = cy * w
    for cx = 0, w - 1 do
      grid[row + cx] = openCell(map, cx, cy, surfing)
    end
  end
  return grid, w, h
end

local function fits(grid, gw, x, y, w, h)
  for cy = y, y + h - 1 do
    local row = cy * gw
    for cx = x, x + w - 1 do
      if not grid[row + cx] then return false end
    end
  end
  return true
end

-- Build the record the renderer reads: the two mons' cells and, in world
-- pixels, the centre of each and of the pair.
local function place(shape, x, y)
  local ex, ey = x + shape.enemy[1], y + shape.enemy[2]
  local px, py = x + shape.player[1], y + shape.player[2]
  local arena = {
    shape = shape.id,
    x = x, y = y, w = shape.w, h = shape.h,
    enemyCell = { ex, ey },
    playerCell = { px, py },
    -- world-pixel centres of the two cells a mon stands on
    enemy = { ex * CELL + CELL / 2, ey * CELL + CELL / 2 },
    player = { px * CELL + CELL / 2, py * CELL + CELL / 2 },
  }
  arena.mid = { (arena.enemy[1] + arena.player[1]) / 2,
                (arena.enemy[2] + arena.player[2]) / 2 }
  return arena
end

-- ------- can the two of them actually be SEEN there
--
-- The camera sits low and far back on one side, so what hides a mon is not
-- what is on its own tile -- it is anything TALL between the camera and it.
-- A tree two cells to the south-east blocks the near mon completely while
-- every cell of the arena is open ground.
--
-- So the line from the eye to each mon is walked in short steps and the
-- terrain height under each step is compared with how high the line is
-- there. Three lines per mon -- to its feet, its middle and its head --
-- because a hedge that clears the head still cuts the body in half.
--
-- Grass and flowers are deliberately not obstacles: they stand at ankle
-- height, they are what a field looks like, and a mon standing in them
-- reads as standing in a field rather than as being hidden by one.
BattleArena.SAMPLE_STEP = 4      -- world pixels along the line
BattleArena.MON_H = 16           -- how tall a mon stands, in world pixels
BattleArena.CLEAR_EPS = 1.5      -- slack, so a flush kerb is not an obstacle
BattleArena.LEVEL_EPS = 0        -- how much step a footprint may hide (see levelled)

-- A TREE IS NOT GROUND, AND `groundAt` ANSWERS THE GROUND UNDER IT.
--
-- In-game location: Route 119, the wooded river route.  Measured against
-- everything the mesher actually stands on a cell -- the shapes and the
-- round stamps below -- 589 of 1,565 sampled battles (37.6%), on 60 of the
-- 81 outdoor maps, hide a mon behind something drawn that the old test
-- could not see.  With this and the stamp pass it is 19 (1.2%) on 5 maps.
--
-- `VoxelScene.groundAt` is the height a WALKER stands at, which is exactly
-- the wrong question here.  Everything this mode stands up as a hull -- a
-- tree crown, a trunk, a rock column, a barrel, a signpost -- has its cell
-- marked `skip`, and `groundAt` on a skipped cell deliberately answers the
-- datum the stamp STANDS ON (`Structures.stampGround`, so a walker is not
-- lifted onto a chimney).  Route 101's border canopies are drawn 32px tall
-- on ground at 6, and `groundAt` answered 6 for every one of them, so the
-- sightline walked straight through the tree line and reported a clear shot.
-- That is the whole of "trees are blocking the view": the test could not see
-- a tree.
--
-- What the MESHER draws is the shape's own top, and `ChunkMesher.heightAt`
-- reads `S.runs[k]` first and the tile's shape after it -- so ask the same
-- two fields, per CELL, taking the tallest of its four tiles: a cell is two
-- columns wide in each direction and a crown filling half of one still
-- crosses the lens.
--
-- Built as one flat grid per search, the way `openGrid` is, so the ray steps
-- are array lookups.  It replaces a `pcall` into `groundAt` per step, and a
-- search runs hundreds of rays, so this is CHEAPER than what it displaces --
-- which matters, because the player is waiting on it when a battle starts.
-- Measured over `BattleArena.find` from every seventh walkable cell, the
-- whole search including the new level and out-of-doors tests: Route 124
-- 64.1ms -> 3.8ms, Route 119 30.5 -> 5.5, Rustboro 5.0 -> 3.5.
--
-- `keyOf` is Structures' own tile key, repeated here rather than imported:
-- it is two constants and a multiply, and `S.shapeAt`/`S.runs` are already
-- read this way by the offline relief tools.
local function tileKey(tx, ty) return (ty + 64) * 4096 + (tx + 64) end

-- One record per search: the drawn top of every cell, built in a single pass
-- because it is one walk of a table the height model has already built, and
-- the walk floor MEMOISED, because `groundAt` is not a lookup -- it reads the
-- tile shape, asks whether the cell is a stair and interpolates a flight --
-- and the level test below asks for the same eighteen cells over and over as
-- the search closes in on the player.
local function stageGrid(map)
  local w, h = map.widthCells, map.heightCells
  local g = { w = w, h = h, top = {}, floor = {} }
  local okS, S = pcall(V.require("Structures").forMap, map)
  if not (okS and S and S.shapeAt) then return g end
  local runs, shapes, top = S.runs or {}, S.shapeAt, g.top
  for cy = 0, h - 1 do
    local row = cy * w
    for cx = 0, w - 1 do
      local t = 0
      for dy = 0, 1 do
        for dx = 0, 1 do
          local k = tileKey(cx * 2 + dx, cy * 2 + dy)
          local run, s = runs[k], shapes[k]
          if run and type(run.h) == "number" and run.h > t then t = run.h end
          if s and type(s.h) == "number" and s.h > t then t = s.h end
        end
      end
      top[row + cx] = t
    end
  end

  -- ...AND THE TREES ARE NOT IN THE HEIGHT FIELD AT ALL.
  --
  -- In-game location: Route 120's wood, at (4,16) -- the arena every one of
  -- the fixes above agrees is the right one, dry and level and proved clear,
  -- and the enemy card comes out ENTIRELY behind one green column.
  --
  -- A tree in this mode is a ROUND STAMP.  `Structures` lifts the drawing
  -- off its cells into a hull, marks those cells `skip`, and appends the
  -- hull to `S.roundStamps`; the SHAPE left behind on the cell then carries
  -- the height of the terrain column, not of the tree.  Route 120's cell
  -- (8,24) is a `cylinder` with `h = 16` standing under a crown drawn three
  -- courses tall, so the loop above read one course of ordinary ground where
  -- the picture has a tree, and every ray sailed through the wood.
  --
  -- A stamp knows its own extent and nothing else does: `mx`/`mz` its centre
  -- in world pixels, `r` its radius, `my` the surface it stands on, `quads`
  -- its geometry with y in each vertex.  Its top is `my` plus the tallest
  -- vertex.  The quad tables are SHARED templates -- `roundCache` hands the
  -- same table to every tree of a kind -- so the maximum is memoised on the
  -- table and actually measured a handful of times for a whole map (Route
  -- 120: 1,185 stamps, 9 distinct templates).
  local capTop = {}
  local stamps = S.roundStamps
  for i = 1, (stamps and #stamps or 0) do
    local st = stamps[i]
    local quads = st.quads
    if quads and st.mx and st.mz then
      local hh = capTop[quads]
      if hh == nil then
        hh = 0
        for qi = 1, #quads do
          local q = quads[qi]
          for vi = 1, 4 do
            local v = q[vi]
            if v and v[2] and v[2] > hh then hh = v[2] end
          end
        end
        capTop[quads] = hh
      end
      local t = (st.my or 0) + hh
      local sr = st.r or 8
      local cx0 = math.floor((st.mx - sr) / CELL)
      local cx1 = math.floor((st.mx + sr - 1) / CELL)
      local cy0 = math.floor((st.mz - sr) / CELL)
      local cy1 = math.floor((st.mz + sr - 1) / CELL)
      if cx0 < 0 then cx0 = 0 end
      if cy0 < 0 then cy0 = 0 end
      if cx1 > w - 1 then cx1 = w - 1 end
      if cy1 > h - 1 then cy1 = h - 1 end
      for cy = cy0, cy1 do
        local row = cy * w
        for cx = cx0, cx1 do
          if t > top[row + cx] then top[row + cx] = t end
        end
      end
    end
  end
  return g
end

-- The walk height of one cell, through the search's memo.
local function floorAt(g, map, cx, cy)
  local i = cy * g.w + cx
  local z = g.floor[i]
  if z == nil then
    local ok, v = pcall(V.require("VoxelScene").groundAt, map, cx, cy)
    z = (ok and v) or 0
    g.floor[i] = z
  end
  return z
end

local function heightAt(g, wx, wz)
  local cx, cy = math.floor(wx / CELL), math.floor(wz / CELL)
  if cx < 0 or cy < 0 or cx >= g.w or cy >= g.h then
    -- off the map the border ring is drawn, and on most outdoor maps that
    -- ring is trees; treat it as solid so an arena is never framed through it
    return 32
  end
  return g.top[cy * g.w + cx] or 0
end

-- Whether the segment from `eye` to (tx, ty, tz) clears what is drawn.
local function lineClear(g, eye, tx, ty, tz)
  local dx, dy, dz = tx - eye[1], ty - eye[2], tz - eye[3]
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  if len <= 1 then return true end
  local steps = math.ceil(len / BattleArena.SAMPLE_STEP)
  -- skip the ends: the eye is in open air by construction and the last step
  -- is the mon's own tile, which it is standing on
  for i = 1, steps - 1 do
    local t = i / steps
    local wx = eye[1] + dx * t
    local wy = eye[2] + dy * t
    local wz = eye[3] + dz * t
    if heightAt(g, wx, wz) > wy + BattleArena.CLEAR_EPS then return false end
  end
  return true
end

-- ...AND THE CAMERA HAS TO BE STANDING ON THE MAP.
--
-- The sightline test above walks from the eye TOWARD each mon and never asks
-- where the eye itself is.  Five blocks back is further than the edge of a
-- small map: on Route 101 -- twenty cells square -- the search's own pick put
-- the seat at cell (20,21), which is off the map entirely, inside the border
-- ring the engine repeats round every layout and this mode extrudes into
-- trees.  The shot then looks out of a hedge, and both Pokemon are behind it.
--
-- The sightline could not catch it: off the map `heightAt` answers 32, and
-- the eye sits at 37.9 -- above that by four pixels -- so every step of the
-- ray cleared the number the test had, while the geometry actually drawn
-- there is a tree line twice as tall.  The honest test is not a taller
-- number, it is that a camera has to be inside the world it is filming.
--
-- Measured over the 81 outdoor Hoenn maps: 12 of the 79 that stage a fight at
-- all seated the camera off the map -- Dewford, Fallarbor, Fortree, Mossdeep,
-- Routes 101/116/121/122, Southern Island and four underwater layouts.  With
-- this test and the short-lens pass below, 3 are left, all of them layouts too
-- small to stand back from at all.
--
-- This is part of CLEARANCE rather than of `fits`, which means it only ever
-- RANKS spots: BattleArena.search walks the whole map demanding clearance and
-- then walks it again without, so a map whose every arena seats the camera
-- outside it keeps the arena it had rather than losing its 3D battle.  The
-- same 79 maps stage a fight after this as before it.
local function eyeOnMap(map, eye)
  if not (map and eye) then return true end
  local cx, cy = math.floor(eye[1] / CELL), math.floor(eye[3] / CELL)
  local ok, inside = pcall(map.inBounds, map, cx, cy)
  return (not ok) or inside and true or false
end

-- The height the two cards are hung at: `BattleScene.groundY` takes the
-- ground under the PLAYER's cell and stands both mons on it, so that is the
-- floor this arena's shot is composed on.
local function arenaFloor(g, map, arena)
  return floorAt(g, map, arena.playerCell[1], arena.playerCell[2])
end

-- Whether both mons would be in plain view from the battle camera.
--
-- ...AND THE SHOT IS TAKEN FROM THE ARENA'S OWN FLOOR, not from the world
-- datum.
--
-- In-game location: Lavaridge Town, Route 111's mesa, Route 120's ridge --
-- anywhere the ground a fight happens on is not at zero.
--
-- The rig was built with `groundY = 0` while the marks were tested at
-- ABSOLUTE y = 1, 8 and 16.  Heights in this model are absolute, so on a
-- terrace three courses up that ran the entire test 48 pixels underground:
-- the eye sat at 37.9 with the arena's own floor at 48, every step of every
-- ray hit terrain, and clearance failed for every candidate on the raised
-- half of the map.  The search then fell through to the unproved pass, which
-- is why the raised maps looked as though nothing was being checked --
-- nothing was.  Route 111 is the extreme: exactly ONE spot on a 40x140 route
-- passed, a pond at the far south end, and it was the arena for a battle
-- started anywhere on the map.
function BattleArena.clearance(map, arena, g)
  local BattleCam = V.require("BattleCam")
  g = g or stageGrid(map)
  local floor = arenaFloor(g, map, arena)
  -- the CANONICAL shot: whether a fight fits somewhere is a fact about the
  -- ground, so it must not depend on the drift's phase or on where the
  -- player last swung the camera (see BattleCam.rig's third argument)
  local ok, rig = pcall(BattleCam.rig, arena, floor, true)
  if not (ok and rig and rig.eye) then return true end
  local eye = rig.eye
  if not eyeOnMap(map, eye) then return false end
  -- ...AND OUT OF DOORS.
  --
  -- In-game location: Rustboro City.  `eyeOnMap` asks whether the seat is
  -- inside the LAYOUT; it never asked whether it is inside a HOUSE.  A
  -- battle staged in the north of that city came out BLACK -- mean RGB
  -- (26,22,14), every pixel of it the unlit underside of a facade -- with
  -- nothing wrong along either sightline: the eye simply had a wall in front
  -- of it.  Rustboro is nine buildings in a forty-cell town, so five blocks
  -- back from an arena in the north lands inside one about as often as not,
  -- and the search's own answer there moves from (21,4) to (21,3) once this
  -- is asked.
  --
  -- The drawn-height grid answers this for nothing -- it is the same lookup
  -- the rays already make -- so ask it: whatever is drawn at the seat has to
  -- be BELOW the seat.
  if heightAt(g, eye[1], eye[3]) > eye[2] - BattleArena.CLEAR_EPS then
    return false
  end
  local H = BattleArena.MON_H
  for _, mark in ipairs({ arena.player, arena.enemy }) do
    for _, hy in ipairs({ 1, H * 0.5, H }) do
      if not lineClear(g, eye, mark[1], floor + hy, mark[2]) then
        return false
      end
    end
  end
  return true
end

-- ------- ...and the ground under them has to be ONE FLOOR
--
-- In-game location: Route 119's riverbank and Route 120's ridge, where the
-- footprint straddled a 20-pixel step.
--
-- Both mons are hung at ONE height -- `BattleScene.groundY` takes the
-- player's cell and stands both cards there -- so a footprint that spans two
-- terraces puts the far card either buried in the step or floating over it.
-- The APRON counts as much as the two cells do: the row behind the far mon
-- is the horizon the shot is composed against, and a course rising through
-- it reads as the mon standing in a hole.
--
-- Measured as the drawn floor over the whole footprint, and demanding it be
-- one number: 161 of 1,565 sampled battles, on 19 maps, span a step, and 64
-- of them put the two MON CELLS at different heights.
--
-- The WHOLE FOOTPRINT, not just the two cells a mon stands on.  A weaker
-- form -- the two mon cells alone, which is the half that cannot be faked
-- because both cards hang at one height -- was written as a second pass
-- underneath this one and MEASURED: over all 518 maps it changed nothing at
-- all, not one arena, because wherever the pair is stepped the footprint
-- round them is too and the pass above has already moved on.  It is not
-- here, because a pass that provably never fires is a pass nobody can
-- maintain.  The number it was chasing is in the census either way: mon
-- cells at different heights, 64 of 1,565 before this change and 8 after.
--
-- A PASS rather than a gate (see PASSES): a map whose every arena is stepped
-- keeps the arena it had rather than losing its 3D battle.  Route 101 is why
-- that matters -- its ground steps 6px every few cells, so NO 3x6 footprint
-- anywhere on the map is level, and the spot it settles on instead puts the
-- pair at one height with the only riser in the western apron column, behind
-- them from a camera that sits east.
function BattleArena.levelled(map, arena, g)
  g = g or stageGrid(map)
  local lo, hi
  for cy = arena.y, arena.y + arena.h - 1 do
    for cx = arena.x, arena.x + arena.w - 1 do
      local z = floorAt(g, map, cx, cy)
      if lo == nil or z < lo then lo = z end
      if hi == nil or z > hi then hi = z end
    end
  end
  return ((hi or 0) - (lo or 0)) <= BattleArena.LEVEL_EPS
end

-- The nearest arena to (fromX, fromY) -- the player's cell -- or nil when
-- the map has room for neither shape.
--
-- Distance is measured from the player to the arena's MIDPOINT, so "nearest"
-- means the fight is staged as close to where it was triggered as the ground
-- allows, rather than merely having a corner nearby.
--
-- Both shapes are searched over the whole map before the next one is tried:
-- a wide arena on the far side of a route still beats a narrow one
-- underfoot, because the wide one is the shot this mode is framed for.
function BattleArena.find(map, fromX, fromY, surfing)
  if not (map and map.widthCells) then return nil end

  -- the authored spot wins outright when the map has one and it still holds
  local pick = authoredFor(map.id)
  -- `false` is an authored REFUSAL: a map looked at and found to have nowhere
  -- a fight can be seen, with no other floor to borrow. Declining is the
  -- honest answer -- the battle draws on the plain screen -- and it has to be
  -- said explicitly, because the fallback search below would otherwise go and
  -- find one of the bad spots that were already rejected by eye.
  if pick == false then return nil end
  if pick then
    local shape = nil
    for _, s in ipairs(BattleArena.SHAPES) do
      if s.id == (pick.shape or "wide") then shape = s end
    end
    -- an entry may point at another floor of the same cave or building; the
    -- arena is then measured against THAT map, and carries it
    local host = map
    if shape and pick.map and pick.map ~= map.id then
      local ok, other = pcall(function()
        local Game = require("src.core.Game")
        return require("src.world.MapLoader").load(Game.data, pick.map)
      end)
      host = (ok and other) or nil
    end
    if shape and host then
      -- An authored spot is checked with WATER COUNTING AS GROUND, whatever
      -- the player is doing. The surfing test exists to stop the automatic
      -- search staging a walker's fight out at sea; an authored entry was
      -- chosen and looked at by a person, so if it is on water that is the
      -- point of it -- the surf routes fight in the middle of their own
      -- ocean rather than on a scrap of beach at the edge of the map. Land
      -- entries are unaffected: land passes the test either way.
      local grid, gw = openGrid(host, true)
      if fits(grid, gw, pick.x, pick.y, shape.w, shape.h) then
        local arena = place(shape, pick.x, pick.y)
        arena.map = host
        -- which camera rig this spot is framed for; nil is the default long
        -- lens, "close" the short one small rooms need (see BattleCam)
        arena.cam = pick.cam
        return arena
      end
    end
  end

  local found = BattleArena.search(map, fromX, fromY, surfing)
  if found then found.map = map end
  return found
end

-- The arena at a given north-west corner, whatever the map says about it.
-- The authoring tool's manual override: a spot chosen by eye rather than by
-- the search, so it can be photographed and judged before it is written down.
function BattleArena.at(x, y, shapeId)
  for _, shape in ipairs(BattleArena.SHAPES) do
    if shape.id == (shapeId or "wide") then return place(shape, x, y) end
  end
  return nil
end

-- The nearest arena the map can offer, preferring one the pair can be SEEN
-- in. Passes rather than one score: a clear arena on the far side of a
-- route beats an obstructed one underfoot, because being able to see the
-- fight is the point, but an obstructed one still beats no battle at all.

-- Where the LONG lens would put the eye for a candidate, so a pass can ask
-- whether that seat is off the map without building the shot twice.
local function longLensEye(arena)
  local BattleCam = V.require("BattleCam")
  local saved = arena.cam
  arena.cam = nil
  local ok, rig = pcall(BattleCam.rig, arena, 0, true)
  arena.cam = saved
  return (ok and rig and rig.eye) or nil
end

-- The passes, in the order a spot is looked for.
--
-- The first is the long lens with the shot proved clear, which is the shot
-- this mode is composed for and what almost every map gets.
--
-- The second is the SHORT LENS, and it is here for exactly one failure: a map
-- the long lens cannot stand back from.  Five blocks behind the near mon is
-- off the edge of an eighteen-by-ten layout, and a camera outside the map
-- films the border ring rather than the fight (see eyeOnMap).  An authored
-- entry has always been able to ask for the short rig by name (`cam =
-- "wide"`); the automatic search never could, so eight of Hoenn's outdoor maps
-- -- Route 101, Dewford, Lavaridge, Mt Pyre's summit, Route 121, Southern
-- Island and the two Abandoned Ship floors -- staged every battle from a seat
-- outside the map.  Both rigs are solved against the same
-- four anchors, so this is a choice of lens and distance and not of
-- composition; the mons render a bit over half a tile rather than a whole
-- one, which is the price and the reason this is not simply tried everywhere.
--
-- Gated on the long lens's OWN seat being off the map, deliberately.  A spot
-- the long lens rejected for a blocked sightline is not a spot the short one
-- has any business rescuing -- a hedge in the way is a hedge in the way -- and
-- without the gate twelve Hoenn maps that stage a perfectly good long shot
-- today, Route 101 and Lavaridge among them, would quietly swap to the small
-- pair.
--
-- The third is the long lens with the clearance test given up, which is where
-- a map that can satisfy neither ends up -- exactly where it ended up before
-- any of this: an unproved shot beats no 3D battle.
--
-- FLATNESS COMES FIRST, and is its own pass (see BattleArena.levelled).  A
-- level footprint is what almost every map can offer, so asking for it first
-- costs nothing where it is available and is given up immediately where it
-- is not.  It is deliberately NOT folded into `fits`: that would make a
-- stepped map stage no battle at all, and Route 120's ridge is stepped
-- everywhere the long lens can also see.
local PASSES = {
  { clear = true,  level = true,  cam = nil },
  { clear = true,  level = false, cam = nil },
  { clear = true,  level = false, cam = "wide", onlyIfLongLensOffMap = true },
  { clear = false, level = false, cam = nil },
}

function BattleArena.search(map, fromX, fromY, surfing, wantClear)
  local grid, gw, gh = openGrid(map, surfing)
  -- built on first use: a map with no candidate rectangle at all never pays
  -- for the drawn-height grid
  local stage
  local function stageFor()
    if not stage then stage = stageGrid(map) end
    return stage
  end
  for _, shape in ipairs(BattleArena.SHAPES) do
    for _, pass in ipairs(PASSES) do
      -- the authoring tool asks for a PROVED spot or none, so it stops where
      -- the proof does -- before the unproved pass runs, not after it has
      -- already found something
      if wantClear and not pass.clear then return nil end
      local best, bestD = nil, nil
      for y = 0, gh - shape.h do
        for x = 0, gw - shape.w do
          if fits(grid, gw, x, y, shape.w, shape.h) then
            local mx = x + (shape.w - 1) / 2
            local my = y + (shape.h - 1) / 2
            local dx, dy = mx - fromX, my - fromY
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then
              local cand = place(shape, x, y)
              -- the lens this pass is asking about, carried on the record so
              -- BattleCam.rigFor answers with it here AND when the battle is
              -- actually shot
              cand.cam = pass.cam
              local allowed = true
              if pass.onlyIfLongLensOffMap then
                allowed = not eyeOnMap(map, longLensEye(cand))
              end
              -- flatness first: eighteen height lookups reject more
              -- candidates than six rays do, and cost less
              if allowed and pass.level then
                allowed = BattleArena.levelled(map, cand, stageFor())
              end
              if allowed and pass.clear then
                allowed = BattleArena.clearance(map, cand, stageFor())
              end
              if allowed then
                best, bestD = cand, d
              end
            end
          end
        end
      end
      if best then return best end
    end
  end

  -- ------- LAST RESORT: A MAP WITH NO DRY GROUND ON IT.
  --
  -- In-game location: Route 122, the sea below Mt Pyre -- 789 water cells and
  -- 21 of shore, none of them three wide.
  --
  -- Water is not a floor for a walker (see `openCell`), and on a route that
  -- is almost all sea that leaves no arena at all, so the fight would fall
  -- back to the flat screen.  For Route 134 that is right and nothing is
  -- lost: you cannot BE on Route 134 without surfing.  For Route 122 you can
  -- -- the Mt Pyre shore is walkable -- and a wild battle there would have
  -- lost its 3D staging outright.
  --
  -- So the surfing search is asked once more before giving up.  It is the
  -- same doctrine the unproved pass above already runs on -- an imperfect
  -- shot beats no 3D battle -- and it cannot bring the reported defect back,
  -- because it only ever runs when every dry pass over the whole map has
  -- already failed.  A fight on the open sea is not a weird place to stage
  -- one when the map IS the open sea; it was only ever wrong as a choice
  -- made while dry ground was standing right there.
  --
  -- Terminates by construction: the retry runs with `surfing` true, and that
  -- branch cannot reach this one.
  if not surfing then
    return BattleArena.search(map, fromX, fromY, true, wantClear)
  end
  return nil
end

return BattleArena
