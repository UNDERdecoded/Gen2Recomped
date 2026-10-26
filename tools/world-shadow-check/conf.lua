function love.conf(t)
  assert(os.getenv("WORLD_SHADOW_QA_GUARDED") == "1", "use the guarded shadow checker")
  t.identity = assert(os.getenv("POKEPORT_IDENTITY"))
  t.window.title = "World anchored shadow qualification"
  t.window.width, t.window.height, t.window.vsync = 640, 480, 0
  t.modules.audio = false
end
