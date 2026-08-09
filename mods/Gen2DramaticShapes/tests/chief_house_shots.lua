-- Scratch driver: shots of the Celadon chief's house, for the display
-- cabinet and long table voxelizations.  Three viewpoints -- the
-- cabinet rank along the north wall, the long table in the middle of
-- the room, and a wide shot with both in frame.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/chief_house_shots.lua \
--   SHOT_DIR=.scratchpad/chief AB_TAG=after lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/chief")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[chief] DRAMATIC_SHAPE mod not loaded")
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

  -- the cabinets occupy cells 2..5 of rows 0-1; the long table cells
  -- 2..5 of rows 3-4; the player walks rows 2 and 5
  local SCENES = {
    { x = 3, y = 2, face = "up",    label = "cabinets" },
    { x = 5, y = 2, face = "up",    label = "bookcase" },
    { x = 3, y = 5, face = "up",    label = "table" },
    { x = 1, y = 5, face = "right", label = "wide" },
    -- the same rank on CELADON_MANSION_1F, where it stands against the
    -- interior partition and the grids start on an ODD tile row
    { map = "CELADON_MANSION_1F", x = 2, y = 4, face = "up",
      label = "mansion1f" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    for _, rung in ipairs({ 3, 5 }) do
      U.teleport(game, s.map or "CELADON_CHIEF_HOUSE", s.x, s.y, s.face)
      Pipelines.setLevel("voxel", rung)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s_v%d.png"):format(ROOT, s.label, rung)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[chief] capture missed: " .. path) end
    end
  end
  print(("[chief] %d shots into %s"):format(shots, ROOT))
end
