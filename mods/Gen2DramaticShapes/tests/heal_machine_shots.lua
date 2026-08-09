-- Scratch driver: shots of the Pokemon Center healing machines behind
-- the counter, for the center_heal_machine voxelization.  The pair
-- stands at cells (1,0):(2,1) and (6,0):(7,1) of every Center; the
-- nurse aisle (row 2) is the row you can actually face them from, and
-- the public floor south of the counter gives the wide view.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/heal_machine_shots.lua \
--   SHOT_DIR=.scratchpad/healshots AB_TAG=after lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/healmachine")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[heal] DRAMATIC_SHAPE mod not loaded")
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

  local SCENES = {
    { x = 1, y = 2, face = "up",   label = "west_head" },
    { x = 2, y = 2, face = "up",   label = "west_keyboard" },
    { x = 3, y = 2, face = "left", label = "west_side" },
    { x = 6, y = 2, face = "up",   label = "east_head" },
    { x = 3, y = 4, face = "up",   label = "wide" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    for _, rung in ipairs({ 3, 5 }) do
      U.teleport(game, "VIRIDIAN_POKECENTER", s.x, s.y, s.face)
      Pipelines.setLevel("voxel", rung)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s_v%d.png"):format(ROOT, s.label, rung)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[heal] capture missed: " .. path) end
    end
  end
  print(("[heal] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
