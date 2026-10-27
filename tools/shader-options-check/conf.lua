function love.conf(t)
  t.identity = assert(os.getenv("POKEPORT_IDENTITY"), "isolated shader QA identity required")
  assert(t.identity:match("^oasc%-gen2recomp%-qa%-shader%-options%-"))
  t.version = "12.0"
  t.highdpi = true
  t.window.width, t.window.height = 640, 480
  t.window.vsync = 0
  t.modules.audio, t.modules.joystick, t.modules.physics = false, false, false
  t.graphics.renderers = { assert(os.getenv("POKEPORT_GRAPHICS_BACKEND")) }
end
