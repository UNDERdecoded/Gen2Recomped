function love.conf(t)
  t.identity = assert(os.getenv('POKEPORT_IDENTITY'))
  t.window = false
  t.modules.graphics = false
  t.modules.audio = false
  t.modules.joystick = false
  t.modules.physics = false
end
