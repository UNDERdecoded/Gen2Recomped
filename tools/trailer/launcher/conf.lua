-- tools/trailer/launcher -- the launcher's game list and the Monster Walker,
-- recorded for the second trailer (see main.lua for how to run it). Run with
-- APPDATA pointing at a scratch folder: the identity's save folder then lives
-- there and never next to the player's own.
function love.conf(t)
  t.identity = os.getenv("IDENTITY") or "trailer2_launcher"
  t.window.width = tonumber(os.getenv("WIDTH") or "1920")
  t.window.height = tonumber(os.getenv("HEIGHT") or "1080")
  t.window.vsync = 0
  t.window.title = "RetroRecomped"
  t.modules.audio = false
  t.modules.sound = false
end
