-- Scratch driver: shots of Bill's desk, for the `bills_desk`
-- voxelization.  The desk fills cells (1,4) and (2,4) of Bill's house
-- with its chair in the walkable cell (1,5) below it, so these are the
-- angles you can actually stand at: head-on from the floor two cells
-- south, and from either flank.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/bills_desk_shots.lua \
--   SHOT_DIR=.scratchpad/billsdesk AB_TAG=after lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/billsdesk")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[bills] DRAMATIC_SHAPE mod not loaded")
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
    { x = 1, y = 6, face = "up",    label = "headon" },
    { x = 2, y = 6, face = "up",    label = "headon_e" },
    { x = 4, y = 5, face = "left",  label = "east" },
    { x = 0, y = 5, face = "right", label = "west" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    for _, rung in ipairs({ 3, 5 }) do
      U.teleport(game, "BILLS_HOUSE", s.x, s.y, s.face)
      Pipelines.setLevel("voxel", rung)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s_v%d.png"):format(ROOT, s.label, rung)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[bills] capture missed: " .. path) end
    end
  end
  print(("[bills] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
