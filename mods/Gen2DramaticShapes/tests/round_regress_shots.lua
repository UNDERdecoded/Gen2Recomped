-- Scratch driver: one shot of every OTHER user of the round-hull builder
-- (tree canopies, boulders, hedges, stumps, the Center planter), to check
-- that the `can` class's base cut is the identity it is supposed to be for
-- everything that does not ask for it.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/round_regress_shots.lua \
--   SHOT_DIR=.scratchpad/round AB_TAG=after lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/round")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then return end
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
    { map = "VIRIDIAN_FOREST", x = 16, y = 20, face = "up",   label = "forest" },
    { map = "PEWTER_GYM",      x = 4,  y = 10, face = "up",   label = "boulders" },
    { map = "CELADON_GYM",     x = 4,  y = 8,  face = "up",   label = "hedges" },
    { map = "VIRIDIAN_POKECENTER", x = 6, y = 5, face = "up", label = "planter" },
    { map = "PALLET_TOWN",     x = 5,  y = 8,  face = "up",   label = "trees" },
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
      else print("[round] capture missed: " .. path) end
    else
      print("[round] teleport failed: " .. s.map)
    end
  end
  print(("[round] %d shots into %s"):format(shots, ROOT))
end
