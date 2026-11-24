-- PS5 runtime bring-up game (scripts/build_ps5.sh --test-game). Not shipped.
function love.conf(t)
  t.identity = "Gen2RecompPS5Test"
  t.version = "11.5"
  t.window.title = "Gen2Recomped PS5 runtime test"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  t.window.vsync = 1
end
