function love.conf(t)
  t.identity = assert(os.getenv('GET_TEST_IDENTITY'))
  t.version = love.getVersion() >= 12 and '12.0' or '11.5'
  t.window = false
  t.modules.graphics, t.modules.audio, t.modules.joystick, t.modules.physics = false, false, false, false
end
