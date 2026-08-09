-- Scratch driver: shots of the house dining tables and stools, for the
-- band-table + no-desk-part voxelization.  Every generic home places the
-- table at cells (3,3):(4,4) with four stools around it (Blue's house has
-- Daisy seated at hers); Red's and the Copycat's ground floors place the
-- same furniture one cell lower, with the potted plant CUTOUT standing on
-- the tabletop -- the standee the table template must support, not
-- swallow.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/house_furniture_shots.lua \
--   SHOT_DIR=.scratchpad/housefurn AB_TAG=after lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/housefurn")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[housefurn] DRAMATIC_SHAPE mod not loaded")
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
    -- head on: below Blue's table looking north over a stool at it,
    -- Daisy seated at the left one
    { map = "BLUES_HOUSE", x = 3, y = 5, face = "up", label = "blues_front" },
    -- from the east, table and both east stools in profile
    { map = "BLUES_HOUSE", x = 6, y = 3, face = "left", label = "blues_side" },
    -- from the north wall looking south down over the tabletop
    { map = "BLUES_HOUSE", x = 4, y = 2, face = "down", label = "blues_over" },
    -- close beside a stool: seat top, legs and the gap between them
    { map = "BLUES_HOUSE", x = 2, y = 5, face = "up", label = "stool_close" },
    -- Red's table head on from the south: the plant cutout standing on
    -- the modelled tabletop
    { map = "REDS_HOUSE_1F", x = 4, y = 6, face = "up", label = "reds_front" },
    -- and from the east along the stool row, plant in profile
    { map = "REDS_HOUSE_1F", x = 6, y = 4, face = "left", label = "reds_side" },
    -- the Fan Club's four members' chairs round the boardroom table:
    -- from the south of the west pair, both stools stacked in profile
    { map = "POKEMON_FAN_CLUB", x = 1, y = 5, face = "up",
      label = "club_west_pair" },
    -- across the table from the west, both pairs and the octagon between
    { map = "POKEMON_FAN_CLUB", x = 0, y = 3, face = "right",
      label = "club_across" },
    -- close on the east pair from the north, looking down over the seats
    { map = "POKEMON_FAN_CLUB", x = 6, y = 2, face = "down",
      label = "club_over" },
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
      else print("[housefurn] capture missed: " .. path) end
    end
  end
  print(("[housefurn] %d shots into %s"):format(shots, ROOT))
end
