-- Driver: the reported "2D flash when entering a building".
-- Switches voxel mode on, walks through Red's front door, and records for
-- EVERY frame of the warp whether a pipeline owned the world pass.  Any
-- frame with the mode on but no pipeline is a frame the player saw flat.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"
  local Pipelines = require("src.render.Pipelines")

  U.teleport(game, "PALLET_TOWN", 5, 6, "up")
  U.wait(30)
  Pipelines.setLevel("voxel", 2)
  Pipelines.setLevel("tiltshift", 0)
  U.wait(30)
  print("[door] outside -- level:", Pipelines.level("voxel"),
        "pipeline:", tostring(Pipelines.worldPipeline()))
  U.shot(game, DIR .. "/door_0_outside.png")

  local flat, total = 0, 0
  local firstFlatAt = nil
  -- walk onto the doormat and through the warp, sampling every frame
  for i = 1, 90 do
    game.input.state = game.input.state or {}
    U.tap(game, "up")
    U.wait(1)
    total = total + 1
    if Pipelines.level("voxel") > 0 and Pipelines.worldPipeline() == nil then
      flat = flat + 1
      firstFlatAt = firstFlatAt or i
      if flat <= 3 then
        U.shot(game, DIR .. ("/door_flat_frame%d.png"):format(i))
      end
    end
    if i == 45 then U.shot(game, DIR .. "/door_1_mid.png") end
  end

  U.wait(20)
  print("[door] inside map:", game.overworld.map and game.overworld.map.id)
  print("[door] pipeline:", tostring(Pipelines.worldPipeline()))
  print(("[door] RESULT flat frames %d / %d  (first at %s)")
    :format(flat, total, tostring(firstFlatAt)))
  U.shot(game, DIR .. "/door_2_inside.png")
end
