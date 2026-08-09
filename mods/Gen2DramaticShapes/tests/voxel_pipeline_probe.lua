-- Driver: prove the render-pipeline seam end to end.
--
-- Teleports to Pallet Town, screenshots the flat world, engages the
-- DRAMATIC_SHAPE mod's pipeline exactly the way the player does (hotkey 6),
-- screenshots the diorama, then walks the T-SHIFT ladder with hotkey 9.
-- Every gate on the path is printed, so a run that comes back flat says
-- which check refused rather than just looking wrong.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"
  local Pipelines = require("src.render.Pipelines")

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(30)
  U.shot(game, DIR .. "/pipeline_0_flat.png")

  print("[probe] pipelines registered:")
  for _, entry in ipairs(Pipelines.list()) do
    print(("  %-10s label=%-8s world=%s worldPresent=%s present=%s hotkey=%s")
      :format(entry.id, tostring(entry.def.label),
              entry.def.drawWorld ~= nil, entry.def.worldPresent ~= nil,
              entry.def.present ~= nil, tostring(entry.def.hotkey)))
  end

  local defs = game.data.render_pipelines or {}
  print("[probe] voxel available:",
        defs.voxel and defs.voxel.available and defs.voxel.available())

  -- press 6 exactly like the player
  game:keypressed("6")
  print("[probe] after key6 level:", Pipelines.level("voxel"),
        "saved:", game.save.options.pipelines
                  and game.save.options.pipelines.voxel,
        "tilt:", game.save.options.tilt)
  U.wait(30)
  print("[probe] world pipeline:",
        tostring(Pipelines.worldPipeline(game.stack:top(), game.overworld)))
  print("[probe] renderer override:",
        tostring(game.renderer.worldOverride))
  U.shot(game, DIR .. "/pipeline_1_voxel15.png")

  for _, level in ipairs({ 2, 3 }) do
    game:keypressed("6")
    U.wait(25)
    print(("[probe] voxel level %d -> override %s")
      :format(Pipelines.level("voxel"), tostring(game.renderer.worldOverride)))
    U.shot(game, DIR .. ("/pipeline_1_voxel%d.png"):format(level))
  end

  -- tilt-shift ladder over the diorama
  for _, level in ipairs({ 1, 2, 3 }) do
    game:keypressed("9")
    U.wait(20)
    print(("[probe] t-shift level %d"):format(Pipelines.level("tiltshift")))
    U.shot(game, DIR .. ("/pipeline_2_tshift%d.png"):format(level))
  end

  -- and back off: the world must return to the flat draw, not stay stuck
  game:keypressed("9")
  game:keypressed("6")
  U.wait(30)
  print("[probe] back off -- voxel:", Pipelines.level("voxel"),
        "override:", tostring(game.renderer.worldOverride))
  U.shot(game, DIR .. "/pipeline_3_backflat.png")

  print("[probe] done")
end
