-- Scratch driver: shots of the SS Anne's galley barrels, which are Lt.
-- Surge's trash can redrawn on the ship atlas.  Three down the kitchen's
-- east wall at cells (13,5)/(13,7)/(13,9), one in the captain's room at
-- (4,1), and one each in the two ship-interior houses at (7,7).
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/ship_can_shots.lua \
--   SHOT_DIR=.scratchpad/ssanne AB_TAG=after lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/ssanne")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[ship] DRAMATIC_SHAPE mod not loaded")
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
    { map = "SS_ANNE_KITCHEN",       x = 12, y = 11, face = "up",    label = "galley_up" },
    { map = "SS_ANNE_KITCHEN",       x = 12, y = 3,  face = "down",  label = "galley_down" },
    { map = "SS_ANNE_KITCHEN",       x = 11, y = 7,  face = "right", label = "galley_side" },
    { map = "SS_ANNE_CAPTAINS_ROOM", x = 4, y = 4,   face = "up",    label = "captain" },
    { map = "CERULEAN_BADGE_HOUSE",  x = 6, y = 7,   face = "right", label = "house" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    local ok = pcall(U.teleport, game, s.map, s.x, s.y, s.face)
    if ok then
      Pipelines.setLevel("voxel", 5)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s.png"):format(ROOT, s.label)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[ship] capture missed: " .. path) end
    else
      print("[ship] teleport failed: " .. s.map)
    end
  end
  print(("[ship] %d shots into %s"):format(shots, ROOT))
end
