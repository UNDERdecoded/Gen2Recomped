-- Scratch driver: shots of Vermilion Gym's trash cans, for the trash can
-- voxelization.  The fifteen cans stand on odd cell columns 1..9 in cell
-- rows 7, 9 and 11; the sixteenth is up at cell (6,1) beside the leader's
-- platform.  Even columns are open floor, so the player can be parked
-- between two cans and look along a row.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/trash_can_shots.lua \
--   SHOT_DIR=.scratchpad/cans AB_TAG=before lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/cans")
    .. "/" .. (os.getenv("AB_TAG") or "before")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[can] DRAMATIC_SHAPE mod not loaded")
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
    -- head on into the middle of the field, cans left, right and ahead
    { x = 4, y = 12, face = "up",    label = "field" },
    -- close up: standing between two cans of the bottom row
    { x = 2, y = 11, face = "left",  label = "close" },
    -- along the row, so the cans line up in depth
    { x = 4, y = 13, face = "up",    label = "row" },
    -- from the north, looking back down over all three rows
    { x = 4, y = 6,  face = "down",  label = "over" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    for _, rung in ipairs({ 3, 5 }) do
      U.teleport(game, "VERMILION_GYM", s.x, s.y, s.face)
      Pipelines.setLevel("voxel", rung)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s_v%d.png"):format(ROOT, s.label, rung)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[can] capture missed: " .. path) end
    end
  end
  print(("[can] %d shots into %s"):format(shots, ROOT))
end
