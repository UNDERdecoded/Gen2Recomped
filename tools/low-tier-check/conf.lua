function love.conf(t)
  assert(os.getenv("LOW_TIER_QA_GUARDED") == "1", "use the guarded render-budget checker")
  t.identity = assert(os.getenv("POKEPORT_IDENTITY"))
  t.window.title = "LOW tier qualification"
  t.window.width, t.window.height, t.window.vsync = 640, 480, 0
  t.modules.audio = false
end
