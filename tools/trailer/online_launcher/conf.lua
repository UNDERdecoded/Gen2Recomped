-- tools/trailer/online_launcher -- the launcher's Online Hub page, recorded
-- for the online trailer (online_host_code). capture_online.py points
-- APPDATA at its scratch folder, so this identity never touches the
-- player's own saves.
function love.conf(t)
  t.identity = os.getenv("IDENTITY") or "trailer_online_launcher"
  t.window.width = tonumber(os.getenv("WIDTH") or "1920")
  t.window.height = tonumber(os.getenv("HEIGHT") or "1080")
  t.window.vsync = 0
  t.window.title = "RetroRecomped"
  t.modules.audio = false
  t.modules.sound = false
end
