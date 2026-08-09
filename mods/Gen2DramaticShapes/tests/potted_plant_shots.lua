-- Scratch driver: shots of the potted plants, for the plant standee
-- voxelization.  Every Center places three side-by-side pairs on its
-- bottom row -- crowns at cells (0,6)/(1,6), (6,6)/(7,6), (12,6)/(13,6),
-- pots below at y=7 -- and INDIGO_PLATEAU_LOBBY (the MART tileset id,
-- same atlas) lines four of them along its hall at cells (12,10)..(15,10).
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/potted_plant_shots.lua \
--   SHOT_DIR=.scratchpad/plants AB_TAG=after lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/plants")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[plant] DRAMATIC_SHAPE mod not loaded")
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
    -- east of the left pair, looking west along the bottom row: both
    -- plants in profile, crown overhang and pot silhouette side-on
    { map = "VIRIDIAN_POKECENTER", x = 3, y = 6, face = "left",
      label = "pair_side" },
    -- north of the left pair, looking south down over the crowns
    { map = "VIRIDIAN_POKECENTER", x = 1, y = 5, face = "down",
      label = "pair_over" },
    -- head on: standing below the middle pair looking north at it
    { map = "VIRIDIAN_POKECENTER", x = 6, y = 7, face = "up",
      label = "pair_front" },
    -- close up beside the east pair's pot
    { map = "VIRIDIAN_POKECENTER", x = 11, y = 7, face = "right",
      label = "close" },
    -- the Plateau lobby's row of four (MART tileset id), along the row
    { map = "INDIGO_PLATEAU_LOBBY", x = 11, y = 10, face = "right",
      label = "lobby_row" },
    -- and head on from the hall below
    { map = "INDIGO_PLATEAU_LOBBY", x = 13, y = 12, face = "up",
      label = "lobby_front" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    for _, rung in ipairs({ 3, 5 }) do
      U.teleport(game, s.map, s.x, s.y, s.face)
      Pipelines.setLevel("voxel", rung)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s_v%d.png"):format(ROOT, s.label, rung)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[plant] capture missed: " .. path) end
    end
  end
  print(("[plant] %d shots into %s"):format(shots, ROOT))
end
