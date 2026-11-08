-- tools/trailer/online_peer -- a headless "other player" for the online
-- trailer shots (tools/trailer/capture_online.py starts these). Hidden
-- window, no audio; the save directory is redirected to the run folder by
-- main.lua before anything writes.
function love.conf(t)
  t.identity = "trailer_online_peer_" .. tostring(os.getenv("PEER_NAME") or "x")
  t.window.width, t.window.height = 256, 192
  t.window.visible = false
  t.window.vsync = 0
  t.modules.audio = false
  t.modules.sound = false
  t.modules.joystick = false
end
