function love.conf(t)
  t.identity = "portable-surf-mount-render-qa"
  t.window.title = "Portable surf mount render contract QA"
  t.window.width = 240
  t.window.height = 160
  t.window.vsync = 0
  if love.getVersion() >= 12 then
    t.highdpi = true
    t.graphics.gammacorrect = false
  else
    t.window.highdpi = true
    t.gammacorrect = false
  end
  t.modules.audio = false
end
