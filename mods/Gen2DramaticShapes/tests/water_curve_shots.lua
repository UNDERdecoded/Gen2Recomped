-- Scratch driver: water shot with V-CURVE walked OFF..3, to see what the
-- world bend does to the reflective pass.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/water_curve_shots.lua \
--   SHOT_DIR=.scratchpad/watercurve AB_TAG=before lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/watercurve")
    .. "/" .. (os.getenv("AB_TAG") or "after")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[water] DRAMATIC_SHAPE mod not loaded")
    return
  end
  local V = handle.lib
  local DayNight = V.require("DayNight")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")
  local WorldCurve = V.require("WorldCurve")
  local Water = V.require("Water")
  -- WATER_RUNG=sky drops the screen-space march and leaves the sky path, to
  -- tell an artefact of the one from an artefact of the other
  if os.getenv("WATER_RUNG") then Water.setting:sync(os.getenv("WATER_RUNG")) end

  require("src.world.OverworldController").rollEncounter = function() return nil end
  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  TileRenderer.animFrame = function() return 0 end
  DayNight.setting:sync(os.getenv("WATER_TIME") or "night")

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

  -- Stand on the walkable cell just north of the widest run of water on the
  -- map, so a scene is picked by where the water actually is rather than by
  -- a coordinate guessed off the block list.
  local TileShape = V.require("TileShape")
  local function shore(map)
    local def = map.def
    local shapes = TileShape.forMap(map)
    local function classAt(cx, cy)
      local tx, ty = cx * 2, cy * 2
      local s = TileShape.at(map, shapes, map:tileAt(tx, ty), tx, ty)
      return s and s.class
    end
    local best, bestRun = nil, 0
    for cy = 1, def.height * 2 - 1 do
      local run, start = 0, nil
      for cx = 0, def.width * 2 - 1 do
        if classAt(cx, cy) == "water" then
          start = start or cx
          run = run + 1
          if run > bestRun and classAt(cx, cy - 1) ~= "water" then
            bestRun, best = run, { x = start + math.floor(run / 2), y = cy - 1 }
          end
        else
          run, start = 0, nil
        end
      end
    end
    return best
  end

  local SCENES = {
    { map = "PALLET_TOWN",     label = "pallet" },
    { map = "CERULEAN_CITY",   label = "cerulean" },
    { map = "VERMILION_CITY",  x = 18, y = 27, label = "vermilion" },
    { map = "ROUTE_24",        label = "route24" },
    { map = "VIRIDIAN_CITY",   label = "viridian" },
  }

  local shots = 0
  for _, s in ipairs(SCENES) do
    if not s.x then
      -- teleport once so the map is loaded, then let the scan place us
      U.teleport(game, s.map, 1, 1, "down")
      U.wait(4)
      local spot = game.overworld and game.overworld.map and shore(game.overworld.map)
      if spot then s.x, s.y = spot.x, spot.y else s.x, s.y = 1, 1 end
      print(("[water] %s shore at (%d,%d)"):format(s.label, s.x, s.y))
    end
    for _, rung in ipairs({ 3, 4 }) do
      for _, curve in ipairs({ 0, 3 }) do
        U.teleport(game, s.map, s.x, s.y, s.face or "down")
        Pipelines.setLevel("voxel", rung)
        Pipelines.setLevel("tiltshift", 0)
        WorldCurve.setting:setIndex(curve + 1, game)
        settle()
        local path = ("%s/%s_v%d_c%d.png"):format(ROOT, s.label, rung, curve)
        game.capturePath = path
        U.wait(8)
        local f = io.open(path, "rb")
        if f then f:close() shots = shots + 1
        else print("[water] capture missed: " .. path) end
      end
    end
  end
  print(("[water] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
