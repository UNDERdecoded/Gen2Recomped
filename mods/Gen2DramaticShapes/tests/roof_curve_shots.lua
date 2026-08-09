-- Scratch driver: the Cerulean gym and the houses beside it, shot at
-- several camera rungs with V-CURVE walked OFF..3, to see what the world
-- bend does to a building's roof.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/roof_curve_shots.lua \
--   SHOT_DIR=.scratchpad/roofcurve AB_TAG=before lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/roofcurve")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[roof] DRAMATIC_SHAPE mod not loaded")
    return
  end
  local V = handle.lib
  local DayNight = V.require("DayNight")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")
  local WorldCurve = V.require("WorldCurve")

  require("src.world.OverworldController").rollEncounter = function() return nil end
  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  TileRenderer.animFrame = function() return 0 end
  DayNight.setting:sync("day")

  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  local Zoom = require("src.render.Zoom")
  pcall(function()
    game.save.options.zoom = 1
    Zoom.applyOptions(game.save.options)
  end)

  local function settle()
    for _ = 1, 900 do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    for _ = 1, 300 do
      if Voxel.t >= 1 and Voxel.ready and ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    U.wait(30)
  end

  -- the gym door is CERULEAN_CITY (30,19); the bike shop and the row of
  -- houses along the west side give a second, smaller roof in frame
  local SCENES = {
    { map = "CERULEAN_CITY", x = 30, y = 20, face = "up",   label = "gym" },
    { map = "CERULEAN_CITY", x = 27, y = 21, face = "up",   label = "gymwide" },
    { map = "PALLET_TOWN",   x = 5,  y = 6,  face = "up",   label = "house" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    for _, rung in ipairs({ 3, 5 }) do
      for _, curve in ipairs({ 0, 3 }) do
        U.teleport(game, s.map, s.x, s.y, s.face)
        Pipelines.setLevel("voxel", rung)
        Pipelines.setLevel("tiltshift", 0)
        WorldCurve.setting:setIndex(curve + 1, game)
        settle()
        local path = ("%s/%s_v%d_c%d.png"):format(ROOT, s.label, rung, curve)
        game.capturePath = path
        U.wait(8)
        local f = io.open(path, "rb")
        if f then f:close() shots = shots + 1
        else print("[roof] capture missed: " .. path) end
      end
    end
  end
  print(("[roof] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
