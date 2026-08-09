-- Driver: one scene, once per rung of the AA row.
--
-- The AA row is the one setting in this mod whose whole effect is a pixel
-- wide, so it is also the one that cannot be judged from a description. This
-- renders the SAME frame at each rung and writes one PNG per rung; put two of
-- them side by side, magnified, and the row is either doing something or it
-- is not.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/aa_shots.lua \
--   SHOT_DIR=<dir> lovec.exe .
--
-- knobs (env):
--   SHOT_DIR   output directory (created if missing)  (default "shots/aa")
--   AA_MAP     map id                                 (default VIRIDIAN_CITY)
--   AA_SPOT    "x,y[,facing]"                         (default 20,26,up)
--   AA_RUNG    the voxel camera rung                  (default 5, the 75 one)
--
-- The scene defaults to a town at the LOW camera on purpose: roof ridges, the
-- diagonal of a fence and a tree's silhouette against the sky are the edges
-- that stair-step, and 75 degrees is the rung that puts the most of them at an
-- angle to the pixel grid.
--
-- Determinism matters here for the same reason it does in voxel_shots_ab: the
-- three shots differ ONLY by the row under test, or comparing them means
-- nothing. The clock is pinned, the animated tile slots are frozen, the
-- townsfolk are stopped where they stand, and the tilt-shift is held at zero
-- (a gaussian over the frame would smear away the very edges being looked at).
--
-- Nothing here writes the player's options: the row is moved with
-- ModSetting:sync, which moves the cached index and persists nothing.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")
  local OverworldState = require("src.world.OverworldController")

  local ROOT = os.getenv("SHOT_DIR") or "shots/aa"

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[aa] DRAMATIC_SHAPE mod not loaded -- nothing to shoot")
    return
  end
  local V = handle.lib
  local DayNight = V.require("DayNight")
  local AntiAlias = V.require("AntiAlias")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")
  local ShadowMap = V.require("ShadowMap")

  local MAP = os.getenv("AA_MAP") or "VIRIDIAN_CITY"
  local SPOT = os.getenv("AA_SPOT") or "20,26,up"
  local RUNG = math.floor(tonumber(os.getenv("AA_RUNG")) or 5)
  local sx, sy, sf = SPOT:match("^(%-?%d+),%s*(%-?%d+),?%s*(%a*)$")
  sx, sy = tonumber(sx) or 20, tonumber(sy) or 26
  if sf == "" then sf = "up" end

  OverworldState.rollEncounter = function() return nil end

  local NPC = require("src.world.NPC")
  if not NPC.dramaticShapeAaFreeze then
    local inner = NPC.update
    function NPC:update(...)
      self.frozen = true
      return inner(self, ...)
    end
    NPC.dramaticShapeAaFreeze = true
  end
  pcall(love.math.setRandomSeed, 20260801)

  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  TileRenderer.animFrame = function() return 0 end

  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  local Zoom = require("src.render.Zoom")
  pcall(function()
    game.save.options.zoom = 1
    Zoom.applyOptions(game.save.options)
  end)

  local function cameraStill()
    local o = game.overworld
    local c = o and o.camera
    if not c then return true end
    local lx, ly, held = nil, nil, 0
    for _ = 1, 300 do
      if c.x == lx and c.y == ly then
        held = held + 1
        if held >= 10 then return true end
      else
        held = 0
        lx, ly = c.x, c.y
      end
      U.wait(1)
    end
    return false
  end

  -- The camera PITCH, which is the one that caught this driver out. The tween
  -- runs on wall-clock dt and Voxel.t reaching 1 is not the same instant the
  -- angle stops moving, so the first shot of a run came out at 67 degrees
  -- while the two after it were at 75 -- three frames that differ by the
  -- camera, in a comparison whose entire subject is a pixel.
  local function angleStill()
    local last, held = nil, 0
    for _ = 1, 600 do
      if Voxel.angle == last then
        held = held + 1
        if held >= 10 then return true end
      else
        held = 0
        last = Voxel.angle
      end
      U.wait(1)
    end
    return false
  end

  local function settle()
    for _ = 1, 900 do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    for _ = 1, 300 do
      if Voxel.t >= 1 and Voxel.ready and ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    angleStill()
    cameraStill()
    -- the sun map is only redrawn when its inputs move, and the AA row is not
    -- one of them -- so force one pass at the settled camera rather than
    -- comparing a frame against a map fitted a few hundredths of a pixel ago
    if ShadowMap.forget then ShadowMap.forget() end
    U.wait(20)
  end

  DayNight.setting:sync("day")
  U.teleport(game, MAP, sx, sy, sf)
  Pipelines.setLevel("voxel", RUNG)
  Pipelines.setLevel("tiltshift", 0)

  -- Warm up before the FIRST shot, not just between them.
  --
  -- Neighbour maps are requested from inside the render itself
  -- (VoxelScene.prefetch), so an empty build queue right after a teleport
  -- means "nothing has been asked for yet", not "everything is here". The
  -- first capture of a run came out with the map beyond Viridian missing --
  -- a whole tree line absent from one frame of a three-way comparison, which
  -- looks exactly like the row under test doing something enormous. Settling
  -- twice lets the first render request the neighbourhood and the second
  -- drain it.
  settle()
  settle()

  local shots, missed = 0, 0
  for _, samples in ipairs({ 0, 2, 4 }) do
    AntiAlias.setting:sync(samples)
    settle()
    -- AA_TRACE=1 prints the state each shot was taken in. When two shots of a
    -- run disagree by more than the row could account for, this is what says
    -- which input moved -- it is how the camera-tween and the neighbour-mesh
    -- settles above were both found.
    if os.getenv("AA_TRACE") == "1" then
      local Voxel3D = V.require("Voxel3D")
      local o = game.overworld
      local cw, chh = Voxel3D.size()
      print(("[aa] trace samples=%d angle=%.6f fov=%.6f cell=%.4f canvas=%dx%d cam=(%.3f,%.3f) eye=(%.2f,%.2f,%.2f) factor=%.4f")
        :format(samples, Voxel.angle or -1, Voxel3D.fovY or -1,
                Voxel3D.cell or -1, cw or 0, chh or 0,
                o and o.camera and o.camera.x or -1,
                o and o.camera and o.camera.y or -1,
                (Voxel3D.eye or {})[1] or 0, (Voxel3D.eye or {})[2] or 0,
                (Voxel3D.eye or {})[3] or 0, AntiAlias.factor()))
    end
    local path = ("%s/aa_%d.png"):format(ROOT, samples)
    game.capturePath = path
    U.wait(6)
    local f = io.open(path, "rb")
    if f then
      f:close()
      shots = shots + 1
      print(("[aa] %s  samples=%d"):format(path, samples))
    else
      missed = missed + 1
      print("[aa] capture did not reach disk: " .. path)
    end
  end
  -- left where it was found, so a run cannot leak a rung into the next one
  AntiAlias.setting:sync(0)

  print(("[aa] %d shots into %s (%d failed to reach disk)")
    :format(shots, ROOT, missed))
end
