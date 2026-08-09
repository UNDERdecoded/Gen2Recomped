-- Scratch driver: shots of the `bookcase` class across the tilesets that
-- pin it, for the shelf-front relief.  Two of them are NOT shelves --
-- the League's gate walls and the terraces on PLATEAU -- and are here as
-- the control: their courses run edge to edge, so nothing should sink.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/shelf_relief_shots.lua \
--   SHOT_DIR=.scratchpad/shelves AB_TAG=before lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/shelves")
    .. "/" .. (os.getenv("AB_TAG") or "before")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[shelf] DRAMATIC_SHAPE mod not loaded")
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
    { map = "OAKS_LAB",           x = 7, y = 2, face = "up", label = "dojo_lab" },
    { map = "CELADON_MANSION_2F", x = 2, y = 4, face = "up", label = "mansion_2f" },
    { map = "CELADON_MART_2F",    x = 5, y = 5, face = "up", label = "lobby_mart" },
    { map = "MUSEUM_1F",          x = 2, y = 4, face = "up", label = "museum" },
    { map = "VIRIDIAN_MART",      x = 3, y = 5, face = "up", label = "mart" },
    { map = "SS_ANNE_CAPTAINS_ROOM", x = 5, y = 2, face = "up", label = "ship" },
    -- the controls, both of them tilesets that borrow the collapse for
    -- something that is NOT a shelf and say so with `bookcase_relief =
    -- false`: the League's masonry gate walls, and Bill's transporter
    -- drums.  Nothing in either may move.
    { map = "INDIGO_PLATEAU",     x = 2, y = 5, face = "up", label = "plateau" },
    { map = "BILLS_HOUSE",        x = 2, y = 3, face = "up", label = "bills" },
    -- the house shelves: pinned `desk`, NOT `bookcase`, so they go
    -- through the world mesher's box fold and this relief never reaches
    -- them.  Here to show the gap.
    { map = "REDS_HOUSE_1F",      x = 1, y = 2, face = "up", label = "reds" },
    { map = "BLUES_HOUSE",        x = 1, y = 2, face = "up", label = "blues" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    local ok = pcall(U.teleport, game, s.map, s.x, s.y, s.face)
    -- twice: the first load of the session has no mesh to settle against
    pcall(U.teleport, game, s.map, s.x, s.y, s.face)
    if ok then
      Pipelines.setLevel("voxel", 5)
      Pipelines.setLevel("tiltshift", 0)
      settle()
      local path = ("%s/%s.png"):format(ROOT, s.label)
      game.capturePath = path
      U.wait(6)
      local f = io.open(path, "rb")
      if f then f:close() shots = shots + 1
      else print("[shelf] capture missed: " .. path) end
    else
      print("[shelf] teleport failed: " .. s.map)
    end
  end
  print(("[shelf] %d shots into %s"):format(shots, ROOT))
end
