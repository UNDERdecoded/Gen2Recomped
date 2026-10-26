function love.conf(t)
  t.identity=assert(os.getenv('STEPS_QA_IDENTITY'))
  t.console=true;t.window=false
  t.modules.audio=false;t.modules.sound=false;t.modules.graphics=false
  t.modules.joystick=false;t.modules.physics=false
end
