-- Driver: the A/B performance benchmark.
--
-- One scripted, deterministic session that exercises the three things the
-- mod is slow at, and writes the numbers to a JSON file so two runs can be
-- diffed:
--
--   1. LOADING IN      -- engaging the mode from flat: shader compiles,
--                         canvas allocations, the first map's mesh, its
--                         atlas bakes and its glass mask, all at once.
--   2. A NEW AREA      -- walking Pallet -> Route 1 -> Viridian with cold
--                         caches, then walking the SAME route again with
--                         them warm. The gap between the two is the
--                         complaint; closing it is the fix.
--   3. A LOW CAMERA    -- standing still at each pitch rung. The 75 degree
--                         rung puts the horizon in frame, which triples the
--                         sun frustum and hands the sky its disc to draw.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/voxel_bench.lua \
--   DS_PERF=1 BENCH_TAG=baseline lovec.exe .
--
-- knobs (env):
--   DS_PERF     must be set, or lib/Perf.lua stays dark and measures nothing
--   BENCH_TAG   output name, ds_bench/<tag>.json     (default "run")
--   BENCH_HOLD  frames to walk per leg              (default 900)
--
-- THREE THINGS THIS RUN CONTROLS FOR, because a benchmark that does not is
-- measuring the weather:
--
--   * VSYNC OFF. With it on every frame costs exactly one refresh interval
--     and the whole exercise reads as 16.7ms flat, saving or no saving.
--   * THE CLOCK PINNED to day. The day/night cycle changes the sky, the sun
--     angle, the shadow frustum and whether windows are lit -- so an
--     unpinned run compares two different scenes.
--   * ENCOUNTERS OFF. A wild battle mid-walk derails the route and charges
--     its frames to whichever map the script thought it was on. Stubbed on
--     the state class for this process only; nothing is written to disk.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")
  local OverworldState = require("src.world.OverworldController")

  local TAG = os.getenv("BENCH_TAG") or "run"
  -- Route 1 is 36 cells tall and a walk step is 16 frames, so a leg that
  -- means to reach Viridian needs about 1200 -- short of that the "new
  -- area" the benchmark is named for never gets entered.
  local HOLD = math.floor(tonumber(os.getenv("BENCH_HOLD")) or 1300)

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[bench] DRAMATIC_SHAPE mod not loaded -- nothing to measure")
    return
  end
  local V = handle.lib
  local Perf = V.require("Perf")
  if not Perf.enabled then
    print("[bench] DS_PERF is not set -- run with DS_PERF=1 or this measures nothing")
    return
  end
  local loadBytes = V.loadBytes
  local Structures = V.require("Structures")
  local ChunkMesher = V.require("ChunkMesher")
  local Buildings = V.require("Buildings")
  local DayNight = V.require("DayNight")
  local VoxelScene = V.require("VoxelScene")

  -- module internals worth naming that the mod does not time itself
  Perf.wrap(Structures, "forMap", "Structures.forMap")
  Perf.wrap(Buildings, "build", "Buildings.build")
  Perf.wrap(ChunkMesher, "pump", "ChunkMesher.pump")
  Perf.wrap(VoxelScene, "render", "VoxelScene.render")

  if love.window and love.window.setVSync then
    pcall(love.window.setVSync, 0)
  end
  DayNight.setting:sync("day")
  OverworldState.rollEncounter = function() return nil end

  -- ---- the run ------------------------------------------------------

  local function seg(name)
    Perf.setSegment(name)
    -- the frame that STRADDLES a segment boundary belongs to neither: it
    -- carries the teleport, the level change or the report print that
    -- opened it, and charging that to the new segment libels it
    Perf.resync()
  end

  local function settle(frames)
    Perf.setSegment(nil)
    U.wait(frames or 60)
    Perf.resync()
  end

  -- Hold a direction, attributing each frame to the map the player is
  -- STANDING ON as it lands. Crossing a seam mid-leg is the whole point of
  -- the walk, so the segment has to follow the player rather than the
  -- script's idea of where they are.
  local function walk(dir, frames, prefix)
    local last = nil
    for _ = 1, frames do
      local o = game.overworld
      local id = o and o.map and o.map.id
      if id ~= last then
        last = id
        seg(prefix .. ":" .. tostring(id))
        print(("[bench] %s entered %s at frame %d"):format(prefix, tostring(id),
                                                           U.frame()))
      end
      -- press and RELEASE each frame, the way tests/voxel_perf_probe's seam
      -- crossing does: a direction left held accumulates in pressQueue and
      -- the walk stalls where a single tap would have stepped
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
      game.input.state[dir] = false
    end
    local o = game.overworld
    print(("[bench] %s ended on %s at cell (%d,%d)"):format(
      prefix, tostring(o and o.map and o.map.id),
      o and o.player and o.player.cellX or -1,
      o and o.player and o.player.cellY or -1))
    Perf.setSegment(nil)
  end

  print("[bench] tag=" .. TAG .. " loadBytes=" .. tostring(loadBytes))

  -- ORDER MATTERS. The cold walk has to be the first time this session
  -- draws Route 1 and Viridian, so everything before it stays in Pallet
  -- Town -- a map whose caches the walk does not depend on. Measuring a
  -- "first entry" into a map an earlier segment already warmed is the one
  -- way to make this whole benchmark lie.

  -- 1. the flat reference: the game with this mod present but not
  --    drawing. Every later number is only interesting against this one.
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  Pipelines.setLevel("voxel", 0)
  Pipelines.setLevel("tiltshift", 0)
  settle(90)
  seg("flat")
  U.wait(180)

  -- 2. loading in: FULL is what a player picks first and it is the most
  --    expensive configuration there is (tilt-shift to maximum, 3D
  --    battles on). Measured from the frame the level changes, so it
  --    carries the shader compiles, the canvas allocations, the first
  --    mesh, the first atlas bake and the first glass scan together.
  settle(60)
  seg("engage.full")
  Pipelines.setLevel("voxel", 1)          -- FULL
  U.wait(240)
  Perf.setSegment(nil)

  -- 3. the low camera. 75 degrees puts the horizon in frame; the rungs
  --    below it are the control. Standing still, so what is measured is
  --    the frame's own cost and not the walk's mesh streaming.
  for _, rung in ipairs({ 2, 3, 4, 5 }) do   -- 15, 35, 50, 75 degrees
    Pipelines.setLevel("voxel", rung)
    settle(60)                                -- let the tween finish
    seg("pitch:" .. tostring(V.require("VoxelState").ANGLE_LABELS[rung + 1]))
    U.wait(180)
    Perf.setSegment(nil)
  end

  -- 3b. the same low camera at DUSK, which is where the sky costs most:
  --     the horizon is in frame, so the banded region is at its tallest,
  --     and the sun is low enough to be in it -- the disc only draws at
  --     all when it is above the horizon point, so a midday run never
  --     touches that code and would report it as free.
  for _, when in ipairs({ "dusk", "night" }) do
    DayNight.setting:sync(when)
    settle(60)
    seg("pitch:75:" .. when)
    U.wait(180)
    Perf.setSegment(nil)
  end
  DayNight.setting:sync("day")
  settle(30)

  -- 4/5. arriving somewhere new, at the rung that hurts.
  --
  -- Arrival is measured by LOADING each map rather than by walking into
  -- it. Walking would be more lifelike, but Route 1's ledges make a held
  -- direction stall against geometry, so a fixed frame count buys a
  -- different amount of travel on every run -- and a benchmark whose
  -- route drifts cannot compare two runs at all. A load is the same
  -- arrival stripped of the travel: the map swaps, and the next frames
  -- pay for its mesh, its structure analysis, its atlas bake and its
  -- glass mask exactly as they do behind a door fade.
  --
  -- Then the identical list a second time. Every cost in the gap between
  -- the two passes is a cache that was cold, and that gap IS the
  -- complaint.
  Pipelines.setLevel("voxel", 5)             -- 75 degrees
  local TOUR = { "ROUTE_1", "VIRIDIAN_CITY", "ROUTE_2", "ROUTE_22",
                 "VIRIDIAN_FOREST", "PEWTER_CITY" }
  local DWELL = math.max(60, math.floor(HOLD / #TOUR))

  -- Stand in the middle of each map, derived from its own def rather than
  -- written down: a hardcoded cell that falls outside a map teleports the
  -- player nowhere and the segment silently measures the previous map.
  local function centreOf(id)
    local def = game.data.maps and game.data.maps[id]
    if not def then return nil end
    return math.floor(def.width), math.floor(def.height)
  end

  local function tour(prefix)
    for _, id in ipairs(TOUR) do
      local cx, cy = centreOf(id)
      if cx then
        U.teleport(game, id, cx, cy, "up")
        -- the segment opens on the frame AFTER the teleport, so the load
        -- itself is not charged to the arrival it caused
        seg(prefix .. ":" .. id)
        U.wait(DWELL)
        Perf.setSegment(nil)
      else
        print("[bench] skipping unknown map " .. id)
      end
    end
  end

  tour("first")
  tour("revisit")

  -- 6. streaming while walking: the one crossing that is reliably
  --    walkable (tests/voxel_perf_probe crosses the same seam) -- Route 1
  --    south into Pallet, which pulls a neighbour's meshes in mid-stride.
  U.teleport(game, "ROUTE_1", 10, 34, "down")
  settle(120)
  walk("down", 240, "walk")

  -- ---- the report ---------------------------------------------------

  Perf.setSegment(nil)
  Perf.printReport("bench " .. TAG)
  Perf.write(TAG, {
    tag = TAG,
    loadBytes = loadBytes,
    hold = HOLD,
    texturememory = Perf.texturememory or 0,
    canvases = Perf.canvases or 0,
    images = Perf.images or 0,
  })
  print("[bench] done")
end
