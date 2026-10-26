function love.conf(t)
  assert(os.getenv('GEN2_REGISTRY_QA')=='1','use the guarded registry checker')
  t.identity=assert(os.getenv('POKEPORT_IDENTITY'))
  t.window.title='Gen2 registry validation profile'
  t.window.width,t.window.height,t.window.vsync=480,240,1
  t.modules.audio=false
end
