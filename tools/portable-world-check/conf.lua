function love.conf(t)
  t.identity = "portable-oasc-world-qa"
  t.window.title = "Portable OASC world contract QA"
  t.window.width = 288
  t.window.height = 192
  if love.getVersion() >= 12 then
    t.highdpi = true
  else
    t.window.highdpi = true
  end
  t.window.vsync = 0
  if love.getVersion() >= 12 then
    t.graphics.gammacorrect = false
  else
    t.gammacorrect = false
  end
  t.modules.audio = false
end
