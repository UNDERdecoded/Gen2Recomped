-- Scratch driver: shots of the 3RD (third-person) rung -- the eye boomed
-- off the back of the player's head, the player's own card drawn and turned
-- to face it, the boom shortening against walls indoors, and the body
-- turning to face where it walks.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/tp_shots.lua \
--   SHOT_DIR=.scratchpad/tpshots lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/tp")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[tp] DRAMATIC_SHAPE mod not loaded")
    return love.event.quit()
  end
  local V = handle.lib
  local FirstPerson = V.require("FirstPerson")
  local ThirdPerson = V.require("ThirdPerson")
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

  -- the nearest WALKABLE cell (fp_shots' helper): a guessed coordinate
  -- inside a building footprint buries the pivot in the geometry
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
              print(("[tp] (%d,%d) not walkable; standing at (%d,%d)")
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
    -- Pallet Town, mid-street: the player's own card seen from behind, in
    -- each compass direction plus a diagonal (the off-grid case, where a
    -- south-facing card would be edge-on to any orbit camera)
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = math.pi, label = "pallet_north" },
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = 0, label = "pallet_south" },
    { map = "PALLET_TOWN", x = 9, y = 7, yaw = math.pi / 2, label = "pallet_east" },
    { map = "PALLET_TOWN", x = 9, y = 7, yaw = 3 * math.pi / 4,
      label = "pallet_diag" },
    -- the shoreline: the boom over water, reflecting the player
    { map = "PALLET_TOWN", x = 9, y = 12, yaw = 0, label = "pallet_water" },
    -- pitched down, the classic third-person framing; and up, where the
    -- boom has to shorten rather than bury the eye in the ground
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = math.pi,
      pitch = math.rad(35), label = "pallet_down" },
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = math.pi,
      pitch = -math.rad(40), label = "pallet_skyward" },
    -- Route 1: grass and ledges, with the character in frame for scale
    { map = "ROUTE_1", x = 10, y = 28, yaw = math.pi, label = "route1_north" },
    -- interiors: the one place a 48px boom cannot fit, so the collision
    -- march is the whole shot
    { map = "VIRIDIAN_POKECENTER", x = 3, y = 5, yaw = math.pi,
      label = "center_north" },
    { map = "REDS_HOUSE_1F", x = 3, y = 4, yaw = math.pi,
      label = "reds_house" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    place(s.map, s.x, s.y)
    Pipelines.setLevel("voxel", Voxel.TP_LEVEL)
    Pipelines.setLevel("tiltshift", 0)
    settle()
    FirstPerson.yaw = s.yaw
    FirstPerson.pitch = s.pitch or FirstPerson.PITCH_DEFAULT
    U.wait(20)
    print(("[tp] %-16s boom %.1f of %.1f"):format(s.label, ThirdPerson.len,
                                                  ThirdPerson.BOOM))
    if U.shot(game, ("%s/%s.png"):format(ROOT, s.label)) then
      shots = shots + 1
    end
  end

  -- the slide from 1ST to 3RD: the eye walks out of the head rather than
  -- cutting, so the halfway frame is a real camera position
  place("PALLET_TOWN", 13, 14)
  Pipelines.setLevel("voxel", Voxel.FP_LEVEL)
  settle()
  if U.shot(game, ROOT .. "/from_1st.png") then shots = shots + 1 end
  Pipelines.setLevel("voxel", Voxel.TP_LEVEL)
  for _ = 1, 300 do
    if ThirdPerson.out >= 0.5 then break end
    U.wait(1)
  end
  if U.shot(game, ROOT .. "/boom_mid.png") then shots = shots + 1 end
  U.wait(60)
  if U.shot(game, ROOT .. "/boom_out.png") then shots = shots + 1 end

  -- ------- the free walk, with the body turning
  --
  -- Hold forward with the head yawed off-grid: the player must GLIDE (off
  -- the 16px grid, which no grid step can do) and the body must end up
  -- facing its own travel rather than the lens.
  place("PALLET_TOWN", 13, 14)
  Pipelines.setLevel("voxel", Voxel.TP_LEVEL)
  settle()
  local ow = game.stack:top()
  local p = ow.player
  FirstPerson.yaw = 3 * math.pi / 4       -- northeast, deliberately off-grid
  FirstPerson.pitch = FirstPerson.PITCH_DEFAULT
  local x0, y0 = p.px, p.py
  U.hold(game, "up", 90)
  local moved = math.abs(p.px - x0) + math.abs(p.py - y0)
  print(("[tp] walk moved %.1f px; off-grid: %s; body faces %s (camera %s)")
        :format(moved,
                tostring(p.px % 16 ~= 0 or p.py % 16 ~= 0),
                tostring(p.facing), tostring(FirstPerson.compassFacing())))
  if U.shot(game, ROOT .. "/walked.png") then shots = shots + 1 end

  -- strafing: the one case the body facing exists for. Hold RIGHT with the
  -- head due north and the character must walk east showing its flank.
  place("PALLET_TOWN", 13, 14)
  settle()
  FirstPerson.yaw = math.pi
  U.hold(game, "right", 40)
  print(("[tp] strafe: body faces %s, camera looks %s")
        :format(tostring(p.facing), tostring(FirstPerson.compassFacing())))
  if U.shot(game, ROOT .. "/strafe.png") then shots = shots + 1 end

  -- ------- the spin, sampled
  --
  -- Stand still and turn the camera fast, sampling the frame the player's
  -- own card actually draws every rendered frame. A standing body is
  -- pointed along the camera's own yaw, so it must show its back the whole
  -- way round; anything else is the sideways flick. Sampled through the
  -- live rig, so this measures the real thing rather than the arithmetic.
  place("PALLET_TOWN", 13, 14)
  Pipelines.setLevel("voxel", Voxel.TP_LEVEL)
  settle()
  ow = game.stack:top()
  p = ow.player
  local seen, frames = {}, 0
  for _ = 1, 240 do
    FirstPerson.lookBy(math.rad(7), 0)      -- ~420 deg/s, a hard flick
    U.wait(1)
    local f = FirstPerson.playerFacing(p.facing, p.px + 8, p.py + 8)
    seen[f] = (seen[f] or 0) + 1
    frames = frames + 1
  end
  local report = {}
  for f, n in pairs(seen) do
    report[#report + 1] = ("%s x%d"):format(f, n)
  end
  table.sort(report)
  print(("[tp] spin: %d frames, card frames seen: %s")
        :format(frames, table.concat(report, ", ")))

  print(("[tp] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
