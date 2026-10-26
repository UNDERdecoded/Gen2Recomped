function love.conf(t)
  assert(os.getenv('GEN2_LIFECYCLE_PROFILE_QA')=='1','use the guarded lifecycle checker')
  t.identity=assert(os.getenv('POKEPORT_IDENTITY'))
  t.window.title='Native Gen2 lifecycle profile'
  t.window.width,t.window.height,t.window.vsync=480,240,1
  t.modules.audio=false
end
