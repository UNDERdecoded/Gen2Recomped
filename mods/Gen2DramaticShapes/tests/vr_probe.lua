-- Scratch driver: exercise the VR stack against the real machine -- the
-- FFI cdefs compile, the loader DLL loads, LOVE's GL context and canvas
-- framebuffers are discoverable, and the OpenXR instance either comes up
-- (headset present) or reports exactly why not (no runtime / no HMD).
-- With a headset connected and the runtime up, it holds a VR session open
-- for ten seconds of frames: diorama first, then the 1ST rung.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/vr_probe.lua \
--   lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[vr] DRAMATIC_SHAPE mod not loaded")
    return love.event.quit()
  end
  local V = handle.lib
  local VR = V.require("VR")
  local VRGL = V.require("VRGL")
  local Voxel = V.require("VoxelState")

  U.teleport(game, "PALLET_TOWN", 10, 12, "down")
  Pipelines.setLevel("voxel", 2)
  U.wait(30)

  -- the GL floor the whole thing stands on
  local okGL = VRGL.load()
  print("[vr] GL interop: " .. tostring(okGL) .. " -- " .. VRGL.status())
  local hdc, hglrc = VRGL.contexts()
  print("[vr] wgl contexts: " .. tostring(hdc) .. " / " .. tostring(hglrc))
  local okC, c = pcall(love.graphics.newCanvas, 64, 64)
  if okC then
    print("[vr] canvas FBO discovery: " .. tostring(VRGL.canvasFBO(c)))
  end

  -- the OpenXR stack, driven by the same row the player would use
  VR.setting:sync(true)
  for _ = 1, 300 do
    U.wait(1)
    if VR.active() or VR.status():find("XR_ERROR") then break end
  end
  print("[vr] status: " .. VR.status())
  print("[vr] active: " .. tostring(VR.active()))

  if VR.active() then
    print("[vr] holding a diorama session for ~5s of frames")
    U.wait(450)
    print("[vr] switching to 1ST for ~5s of frames")
    Pipelines.setLevel("voxel", Voxel.FP_LEVEL)
    U.wait(450)
    print("[vr] still active: " .. tostring(VR.active())
          .. " -- " .. VR.status())
  end

  VR.setting:sync(false)
  U.wait(10)
  print("[vr] after toggle off: " .. VR.status())
  love.event.quit()
end
