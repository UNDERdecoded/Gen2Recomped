-- Scratch driver: shots of the Bike Shop showroom, for the bicycle
-- voxelization.  Two viewpoints -- the north wall (the two bikes drawn
-- INTO the wall band) and the showroom floor (the six standing bikes).
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/bike_shop_shots.lua \
--   SHOT_DIR=.scratchpad/bikes AB_TAG=before lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/bikes")
    .. "/" .. (os.getenv("AB_TAG") or "before")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[bike] DRAMATIC_SHAPE mod not loaded")
    return
  end
  local V = handle.lib
  local DayNight = V.require("DayNight")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")

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
    U.wait(40)
  end

  -- cells: wall bikes ride cell row 0 (tile cols 1-3 and 6-8); the six
  -- floor bikes stand in cell columns 0 and 2, rows 1-2 and 4-5
  local SCENES = {
    { x = 2, y = 2, face = "up",   label = "wall" },
    { x = 3, y = 3, face = "up",   label = "room" },
    { x = 2, y = 4, face = "left", label = "floor" },
    { x = 3, y = 6, face = "up",   label = "wide" },
    -- the two toolboxes, cells (6,6) and (7,7)
    { x = 5, y = 6, face = "right", label = "tools" },
    { x = 6, y = 4, face = "down",  label = "tools2" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    for _, rung in ipairs({ 3, 5 }) do
      U.teleport(game, "BIKE_SHOP", s.x, s.y, s.face)
      Pipelines.setLevel("voxel", rung)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s_v%d.png"):format(ROOT, s.label, rung)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[bike] capture missed: " .. path) end
    end
  end
  print(("[bike] %d shots into %s"):format(shots, ROOT))
end
