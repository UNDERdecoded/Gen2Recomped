-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that a diggable wall is a wall face with floor in front of
-- it, measured against the real Underground rather than asserted; and that the
-- cluster the game spawns lands on those cells, inside the main area, within ten
-- tiles of its centre.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: `TerrainCollisionManager_CheckCollision`
-- returning TRUE for BLOCKED. Read the other way, `canSpawnAt` becomes "a floor
-- cell with a wall beside it" -- which still runs, still returns plausible
-- numbers, and puts every excavation site on the ground instead of in a wall.
-- Section 2 pins the polarity by measuring both readings: the right one keeps
-- 24,824 cells, the inverted one keeps a different number, and section 5 asserts
-- every spawned spot is on a cell the map calls solid.
--
-- Usage: texlua tools/gen4_mining_spots_check.lua [<dataset dir>]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local dir = (arg[1] or "G:/Gen2Recomped/platinum/data/generated"):gsub("[/\\]*$", "") .. "/"
local Spots = require("src.world.Gen4MiningSpots")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function load_(name)
  local chunk, err = loadfile(dir .. name)
  if not chunk then
    io.stderr:write(("could not load %s%s: %s\n"):format(dir, name, tostring(err)))
    os.exit(2)
  end
  return chunk()
end

local maps, layouts = load_("maps.lua"), load_("map_layouts.lua")
local ug = maps["UG"]
if not ug then io.stderr:write("no UG map in this dataset\n"); os.exit(2) end
local blocks = ug.blocks or (layouts[ug.layout] or {}).blocks
local W, H = ug.width, ug.height
local BLOCKED = 255

-- A stand-in for Map that answers blockAt the way the real one does, including
-- border-extending with borderBlock.
local map = {
  blockAt = function(_, x, z)
    if x < 0 or z < 0 or x >= W or z >= H then return BLOCKED end
    return blocks:byte((z * W + x) * 2 + 1)
  end,
}

-- ---------------------------------------------------------------------------
section("1. the constants are underground/defs.h's")
-- ---------------------------------------------------------------------------
ok(Spots.MAIN_AREA_START_X == 32, "MAIN_AREA_START_X should be 32")
ok(Spots.MAIN_AREA_START_Z == 64, "MAIN_AREA_START_Z should be 64")
ok(Spots.MAX_X == 479 and Spots.MAX_Z == 479, "MAX_X/Z should be 479")
ok(Spots.MAX_MINING_SPOTS == 250, "MAX_MINING_SPOTS should be 250")
-- MAX_X/Z and the map's own size have to agree, or the bounds test is guarding
-- a map of a different shape.
ok(W == Spots.MAX_X + 1 and H == Spots.MAX_Z + 1,
   "the Underground is %dx%d but the bounds constants describe %dx%d",
   W, H, Spots.MAX_X + 1, Spots.MAX_Z + 1)

section("2. diggable walls in the real Underground, and the polarity")
local walls, floor, valid = 0, 0, 0
for z = 0, H - 1 do
  for x = 0, W - 1 do
    if map:blockAt(x, z) == BLOCKED then walls = walls + 1 else floor = floor + 1 end
    if Spots.canSpawnAt(map, x, z) then valid = valid + 1 end
  end
end
io.write(("  %d wall cells, %d floor cells, %d diggable\n"):format(walls, floor, valid))
ok(walls == 156142, "expected 156,142 wall cells, got %d", walls)
ok(floor == 74258, "expected 74,258 floor cells, got %d", floor)
ok(valid == 24824, "expected 24,824 diggable cells, got %d", valid)

-- THE CONTROL FOR THE NEIGHBOUR TEST: without it, every main-area wall passes.
local ignoringNeighbours = 0
for z = 0, H - 1 do
  for x = 0, W - 1 do
    if not Spots.inSecretBase(x, z) and x <= Spots.MAX_X - 1 and z <= Spots.MAX_Z - 1
       and map:blockAt(x, z) == BLOCKED then
      ignoringNeighbours = ignoringNeighbours + 1
    end
  end
end
io.write(("  control -- main-area walls ignoring the neighbour test: %d (%.1f%% discarded)\n")
         :format(ignoringNeighbours, (ignoringNeighbours - valid) / ignoringNeighbours * 100))
ok(ignoringNeighbours > valid * 2,
   "the neighbour test discards almost nothing (%d of %d), so it is not the "
   .. "thing selecting these cells", ignoringNeighbours - valid, ignoringNeighbours)

-- THE POLARITY CONTROL: read CheckCollision the other way round and the answer
-- changes. If it did not, the test would be blind to the inversion.
local inverted = {
  blockAt = function(_, x, z)
    if x < 0 or z < 0 or x >= W or z >= H then return 0 end
    return (blocks:byte((z * W + x) * 2 + 1) == BLOCKED) and 0 or BLOCKED
  end,
}
local invertedValid = 0
for z = 0, H - 1 do
  for x = 0, W - 1 do
    if Spots.canSpawnAt(inverted, x, z) then invertedValid = invertedValid + 1 end
  end
end
io.write(("  control -- the same rule with solid/walkable swapped: %d cells\n")
         :format(invertedValid))
ok(invertedValid ~= valid,
   "inverting solid and walkable gives the same %d cells, so this measurement "
   .. "cannot tell the two readings apart", valid)

section("3. the secret-base rectangle is open at both ends")
-- x > 32 and x < 479, so 32 and 479 are OUT and 33 and 478 are IN. An
-- inclusive reading would quietly add the map's outer ring.
ok(Spots.inSecretBase(32, 200) == true, "x = 32 should be secret-base ground")
ok(Spots.inSecretBase(33, 200) == false, "x = 33 should be main area")
ok(Spots.inSecretBase(479, 200) == true, "x = 479 should be secret-base ground")
ok(Spots.inSecretBase(478, 200) == false, "x = 478 should be main area")
ok(Spots.inSecretBase(200, 64) == true, "z = 64 should be secret-base ground")
ok(Spots.inSecretBase(200, 65) == false, "z = 65 should be main area")
ok(Spots.inSecretBase(200, 479) == true, "z = 479 should be secret-base ground")
ok(Spots.inSecretBase(-1, -1) == true, "off-map should be secret-base ground")

section("4. every diggable cell really is a wall with floor beside it")
-- Re-derived independently of canSpawnAt, so the two have to agree.
local wrong = 0
for z = 0, H - 1 do
  for x = 0, W - 1 do
    if Spots.canSpawnAt(map, x, z) then
      local isWall = map:blockAt(x, z) == BLOCKED
      local hasFloor = map:blockAt(x, z + 1) ~= BLOCKED or map:blockAt(x, z - 1) ~= BLOCKED
                    or map:blockAt(x + 1, z) ~= BLOCKED or map:blockAt(x - 1, z) ~= BLOCKED
      if not (isWall and hasFloor) then wrong = wrong + 1 end
    end
  end
end
ok(wrong == 0, "%d cells pass canSpawnAt without being a wall beside floor", wrong)

section("5. the clusters the game would spawn")
local function lcg(seed)
  local s = seed
  return function(n)
    s = (1103515245 * s + 12345) % 2147483648
    if n <= 0 then return 0 end
    return math.floor(s / 65536) % n
  end
end
local RUNS = 300
local counts, failed, offCentre, notWall, inBase, trapOnWall, totalSpots, totalTraps =
      {}, 0, 0, 0, 0, 0, 0, 0
for seed = 1, RUNS do
  local c, why = Spots.spawnCluster(map, lcg(seed * 7919),
                                    { matrixWidth = 15, matrixHeight = 15 })
  if not c then failed = failed + 1
  else
    counts[c.wanted] = (counts[c.wanted] or 0) + 1
    totalSpots = totalSpots + #c.spots
    totalTraps = totalTraps + #c.traps
    -- the centre has to be diggable too: the do/while that picks it retries
    -- until canSpawnAt agrees, so a centre that is not a wall means the loop
    -- gave up and returned one anyway.
    if not Spots.canSpawnAt(map, c.centre.x, c.centre.z) then notWall = notWall + 1 end
    for _, s in ipairs(c.spots) do
      if map:blockAt(s.x, s.z) ~= BLOCKED then notWall = notWall + 1 end
      if Spots.inSecretBase(s.x, s.z) then inBase = inBase + 1 end
      -- the window is `rand(20) + centre - 10`, so -10 .. +9 inclusive
      if s.x < c.centre.x - 10 or s.x > c.centre.x + 9
         or s.z < c.centre.z - 10 or s.z > c.centre.z + 9 then
        offCentre = offCentre + 1
      end
    end
    for _, t in ipairs(c.traps) do
      if map:blockAt(t.x, t.z) == BLOCKED then trapOnWall = trapOnWall + 1 end
    end
  end
end
local spread = {}
for k, v in pairs(counts) do spread[#spread + 1] = ("%d=%d"):format(k, v) end
table.sort(spread)
io.write(("  %d clusters: wanted %s\n"):format(RUNS, table.concat(spread, " ")))
io.write(("  %.1f spots and %.1f traps per cluster on average\n")
         :format(totalSpots / RUNS, totalTraps / RUNS))
ok(failed == 0, "%d of %d clusters failed to spawn", failed, RUNS)
ok(notWall == 0, "%d spawned spots are not on a wall cell", notWall)
ok(inBase == 0, "%d spawned spots landed in secret-base ground", inBase)
ok(offCentre == 0, "%d spawned spots are outside the -10..+9 window", offCentre)
ok(trapOnWall == 0, "%d traps landed inside a wall", trapOnWall)
-- MATH_Rand16(rand, 6) + 6, so six to eleven and nothing else.
for k in pairs(counts) do
  ok(k >= 6 and k <= 11, "a cluster wanted %d spots; the range is 6..11", k)
end
ok((counts[6] or 0) > 0 and (counts[11] or 0) > 0,
   "the spot count is not spanning 6..11 across %d clusters", RUNS)

section("6. the guards bite")
ok(Spots.spawnCluster(map, nil) == nil, "spawnCluster accepted a nil random source")
local allFloor = { blockAt = function() return 0 end }
local c, why = Spots.spawnCluster(allFloor, lcg(1), { matrixWidth = 15, matrixHeight = 15 })
ok(c == nil and why ~= nil,
   "a map with no walls at all did not trip the centre-search limit (got %s)",
   tostring(c))
local tiny = Spots.spawnCluster(map, lcg(1), { matrixWidth = 2, matrixHeight = 2 })
ok(tiny == nil, "a 2x2 matrix leaves no range and should be refused")

section("7. the spots as the overworld actually places them")
-- Gen4Underground.ensureSpots is what the overworld calls; this exercises that
-- rather than spawnCluster directly, because the wiring between them is where a
-- wrong matrix size or a missing save table would hide.
local UG = require("src.world.Gen4Underground")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("platinum")

local function fakeGame()
  return { save = { underground = {} }, data = { maps = maps } }
end
local function fakeOw()
  local started = {}
  return {
    map = { id = "UG", def = { label = "Mystery Zone", width = W, height = H },
            blockAt = map.blockAt },
    player = { cellX = 240, cellY = 240 },
    startSparkle = function(_, x, y) started[#started + 1] = { x = x, y = y } end,
    started = started,
  }, started
end

local placed, onWall, offWall = 0, 0, 0
for seed = 1, 60 do
  local G, ow = fakeGame(), (fakeOw())
  local made = UG.ensureSpots(G, ow, lcg(seed * 5099))
  ok(made == true, "seed %d: ensureSpots did not place anything", seed)
  local spots = UG.spots(G)
  placed = placed + #spots
  for _, s in ipairs(spots) do
    if Spots.canSpawnAt(map, s.x, s.z) then onWall = onWall + 1 else offWall = offWall + 1 end
  end
  -- IDEMPOTENT: the overworld calls this every frame, so a second call must not
  -- re-roll the cave under the player's feet.
  local before = #spots
  UG.ensureSpots(G, ow, lcg(seed * 7))
  ok(#UG.spots(G) == before,
     "seed %d: a second ensureSpots changed the set (%d -> %d)",
     seed, before, #UG.spots(G))
end
io.write(("  60 descents placed %d spots, %d on diggable walls, %d not\n")
         :format(placed, onWall, offWall))
ok(offWall == 0, "%d placed spots are not on a diggable wall", offWall)
ok(placed >= 60 * 6, "only %d spots across 60 descents; 6 is the minimum each",
   placed)

section("8. leaving the cave keeps the set until a day passes, and other cartridges never get one")
do
  local World = require("src.world.Gen4UgWorld")
  local G, ow = fakeGame(), (fakeOw())
  UG.ensureSpots(G, ow, lcg(11))
  local first = #UG.spots(G)
  ok(first > 0, "nothing was placed to test the clear with")
  -- THE CARTRIDGE KEEPS THEM: Mining_LoadSavedMiningSpots reloads the saved
  -- set on the next trip; only Underground_HandleDailyEvents (a day has
  -- passed) re-rolls it. So walking out must not drop the spots...
  ow.map.def.label = "Jubilife City"
  ow.map.id = "C01"
  ok(UG.ensureSpots(G, ow, lcg(11)) == false, "an overworld map placed dig walls")
  ok(#UG.spots(G) == first, "leaving the Underground changed the saved spots (%d -> %d)",
     first, #UG.spots(G))
  -- ...coming back the same day reloads them rather than re-rolling...
  ow.map.def.label, ow.map.id = "Mystery Zone", "UG"
  local saved = UG.spots(G)
  UG.ensureSpots(G, ow, lcg(99))
  ok(UG.spots(G) == saved and #UG.spots(G) == first, "same-day return re-rolled the spots")
  -- ...and a day passing marks the set for a fresh spawn on the next arrival
  ow.map.id = "C01"; ow.map.def.label = "Jubilife City"
  UG.ensureSpots(G, ow, lcg(11))
  World.checkDay(G.save, os.time() + 2 * 86400)
  ok(World.ug(G.save).shouldSpawn == true, "a day passing did not owe a new spawn")
end
do
  GameVersion.set("crystal")
  local G, ow = fakeGame(), (fakeOw())
  ok(UG.ensureSpots(G, ow, lcg(11)) == false,
     "ensureSpots placed dig walls on a non-Gen-4 cartridge")
  ok(#UG.spots(G) == 0, "a Gen 2 save gained %d dig spots", #UG.spots(G))
  GameVersion.set("platinum")
end

section("9. the sparkle pulse")
do
  local G = fakeGame()
  local ow, started = fakeOw()
  UG.ensureSpots(G, ow, lcg(2027))
  local spots = UG.spots(G)
  -- put the player on one of them, so at least one is inside the range
  ow.player.cellX, ow.player.cellY = spots[1].x, spots[1].z
  for _ = 1, UG.SPARKLE_PERIOD - 1 do UG.tickSparkles(G, ow) end
  ok(#started == 0, "the pulse fired after %d ticks; the period is %d",
     #started, UG.SPARKLE_PERIOD)
  UG.tickSparkles(G, ow)
  io.write(("  %d spots, %d sparkled on the tick the period came round\n")
           :format(#spots, #started))
  ok(#started > 0, "the pulse never fired")
  -- only the near ones, and every one it fired is a real spot
  local near, bogus = 0, 0
  for _, s in ipairs(spots) do
    if math.abs(s.x - ow.player.cellX) <= UG.SPARKLE_RANGE
       and math.abs(s.z - ow.player.cellY) <= UG.SPARKLE_RANGE then near = near + 1 end
  end
  for _, f in ipairs(started) do
    if not UG.spotAt(G, f.x, f.y) then bogus = bogus + 1 end
  end
  ok(#started == near, "%d sparkles for %d spots in range", #started, near)
  ok(bogus == 0, "%d sparkles fired on cells with no dig spot", bogus)
  -- a player far away sparkles nothing
  local ow2, started2 = fakeOw()
  ow2.player.cellX, ow2.player.cellY = 40, 470
  for _ = 1, UG.SPARKLE_PERIOD + 1 do UG.tickSparkles(G, ow2) end
  io.write(("  control -- a player across the cave: %d sparkles\n"):format(#started2))
  ok(#started2 < #started,
     "a player %d cells away sparkles as much as one standing on a spot, so the "
     .. "range test is doing nothing", UG.SPARKLE_RANGE * 4)
end

section("10. the overworld really calls it")
-- The two inserts, pinned. Without them everything above is a library nobody
-- runs -- which is the exact shape of the bug pass 130 found, a thing that
-- exists and is not named.
local f = io.open(root .. "../src/world/OverworldController.lua", "rb")
      or io.open("src/world/OverworldController.lua", "rb")
ok(f ~= nil, "could not open OverworldController")
if f then
  local text = f:read("*a"):gsub("\r\n", "\n")
  f:close()
  ok(text:find("UG.ensureSpots(Game, self)", 1, true) ~= nil,
     "nothing places the dig spots: ensureSpots is not called from the overworld")
  ok(text:find("UG.tickSparkles(Game, self)", 1, true) ~= nil,
     "nothing pulses the sparkles, so the spots are invisible")
  ok(text:find("UG.spotAt(Game, fx, fy)", 1, true) ~= nil,
     "nothing opens the mining game: interact does not test for a dig wall")
  ok(text:find("Game.stack:push(screen)", 1, true) ~= nil,
     "the mining screen is never pushed")
  ok(text:find("UG.removeSpot(Game, fx, fy)", 1, true) ~= nil,
     "a dug wall is never spent, so the same spot can be mined forever")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)