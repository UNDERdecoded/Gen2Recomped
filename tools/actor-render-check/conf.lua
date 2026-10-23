function love.conf(t)
  t.identity = "portable-actor-render-qa"
  t.window.title = "Portable actor render contract QA"
  t.window.width = 384
  t.window.height = 256
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
