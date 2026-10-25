function love.conf(t)
  local identity = assert(os.getenv('UPVALUE_TEST_IDENTITY'))
  assert(identity:match('^oasc%-native%-runtime%-qa%-'))
  t.identity = identity
  t.version = '12.0'
  t.window = false
  t.modules.graphics = false
  t.modules.audio = false
  t.modules.joystick = false
  t.modules.physics = false
end
