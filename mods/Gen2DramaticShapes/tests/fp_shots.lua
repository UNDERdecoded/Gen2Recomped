-- Scratch driver: shots of the 1ST (first-person) rung -- the rig standing
-- in the player's head, billboards yawing to face it, the sky meeting the
-- horizon, the shadow box following the look, water seen from eye level,
-- and an interior with its figures.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/fp_shots.lua \
--   SHOT_DIR=.scratchpad/fpshots lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/fp")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[fp] DRAMATIC_SHAPE mod not loaded")
    return love.event.quit()
  end
  local V = handle.lib
  local FirstPerson = V.require("FirstPerson")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")
  local DayNight = V.require("DayNight")

  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  require("src.world.OverworldController").rollEncounter = function() return nil end
  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  TileRenderer.animFrame = function() return 0 end
  DayNight.setting:sync("day")

  local Zoom = require("src.render.Zoom")
  pcall(function()
    game.save.options.zoom = 0
    Zoom.applyOptions(game.save.options)
  end)

  local function settle()
    for _ = 1, 900 do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    for _ = 1, 300 do
      if FirstPerson.blend >= 1 and Voxel.ready
         and ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    U.wait(40)
  end

  -- Teleport to the nearest WALKABLE cell: a guessed coordinate inside a
  -- building footprint buries the eye in the geometry, which is what the
  -- first cut of every Pallet shot did.
  local function place(mapId, x, y)
    U.teleport(game, mapId, x, y, "down")
    local ow = game.stack:top()
    local map = ow and ow.map
    if not map or map:isWalkableCell(x, y) then return end
    for r = 1, 8 do
      for dy = -r, r do
        for dx = -r, r do
          if math.max(math.abs(dx), math.abs(dy)) == r then
            local cx, cy = x + dx, y + dy
            if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy) then
              U.teleport(game, mapId, cx, cy, "down")
              print(("[fp] (%d,%d) not walkable; standing at (%d,%d)")
                    :format(x, y, cx, cy))
              return
            end
          end
        end
      end
    end
  end

  -- yaw is a world bearing: 0 south, pi/2 east, pi north, -pi/2 west
  local SCENES = {
    -- Pallet Town, mid-street: houses, the lab, NPCs -- the town seen
    -- from inside it, in each compass direction plus a diagonal
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = math.pi, label = "pallet_north" },
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = 0, label = "pallet_south" },
    { map = "PALLET_TOWN", x = 9, y = 7, yaw = math.pi / 2, label = "pallet_east" },
    { map = "PALLET_TOWN", x = 9, y = 7, yaw = 3 * math.pi / 4,
      label = "pallet_diag" },
    -- the shoreline: water at eye level, which is where the battle pass
    -- says a low placed camera reads the reflection wrong -- the shot
    -- decides whether 1ST keeps it
    { map = "PALLET_TOWN", x = 9, y = 12, yaw = 0, label = "pallet_water" },
    -- looking up: the sky's bands and the horizon line
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = math.pi,
      pitch = -math.rad(25), label = "pallet_skyward" },
    -- and down: the ground, the feet-level shadow
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = math.pi,
      pitch = math.rad(45), label = "pallet_down" },
    -- Route 1: grass rows and ledges from inside them
    { map = "ROUTE_1", x = 10, y = 28, yaw = math.pi, label = "route1_north" },
    -- an interior: the Center's counter, machines and couch figures
    { map = "VIRIDIAN_POKECENTER", x = 3, y = 5, yaw = math.pi,
      label = "center_north" },
    { map = "VIRIDIAN_POKECENTER", x = 6, y = 4, yaw = -math.pi / 2,
      label = "center_west" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    place(s.map, s.x, s.y)
    Pipelines.setLevel("voxel", Voxel.FP_LEVEL)
    Pipelines.setLevel("tiltshift", 0)
    settle()
    FirstPerson.yaw = s.yaw
    FirstPerson.pitch = s.pitch or FirstPerson.PITCH_DEFAULT
    U.wait(20)
    if U.shot(game, ("%s/%s.png"):format(ROOT, s.label)) then
      shots = shots + 1
    end
  end

  -- one mid-blend shot: step the ladder onto 1ST from 75 and catch the
  -- dive halfway
  place("PALLET_TOWN", 13, 14)
  Pipelines.setLevel("voxel", 5)
  settle()
  Pipelines.setLevel("voxel", Voxel.FP_LEVEL)
  for _ = 1, 300 do
    if FirstPerson.blend >= 0.5 then break end
    U.wait(1)
  end
  if U.shot(game, ROOT .. "/blend_mid.png") then shots = shots + 1 end

  -- ------- the free walk, exercised
  --
  -- Hold forward with the head yawed off-grid and confirm the player
  -- GLIDES: the position moves along the look direction, lands off the
  -- 16px grid (which no grid step can do), and the logical cell follows.
  place("PALLET_TOWN", 13, 14)
  Pipelines.setLevel("voxel", Voxel.FP_LEVEL)
  settle()
  local ow = game.stack:top()
  local p = ow.player
  FirstPerson.yaw = 3 * math.pi / 4       -- northeast, deliberately off-grid
  FirstPerson.pitch = FirstPerson.PITCH_DEFAULT
  local x0, y0, c0x, c0y = p.px, p.py, p.cellX, p.cellY
  U.hold(game, "up", 90)
  U.wait(5)
  local moved = math.abs(p.px - x0) + math.abs(p.py - y0)
  print(("[fp] walk: (%.1f,%.1f) cell(%d,%d) -> (%.1f,%.1f) cell(%d,%d)")
        :format(x0, y0, c0x, c0y, p.px, p.py, p.cellX, p.cellY))
  print(("[fp] walk moved %.1f px; off-grid: %s; diagonal: %s")
        :format(moved,
                tostring(p.px % 16 ~= 0 or p.py % 16 ~= 0),
                tostring(math.abs(p.px - x0) > 8
                         and math.abs(p.py - y0) > 8)))
  if U.shot(game, ROOT .. "/walked.png") then shots = shots + 1 end

  print(("[fp] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
