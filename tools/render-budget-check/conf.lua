function love.conf(t)
  assert(os.getenv("RENDER_BUDGET_QA_GUARDED") == "1", "use the guarded render-budget checker")
  t.identity = assert(os.getenv("POKEPORT_IDENTITY"))
  t.window.title = "Render budget qualification"
  t.window.width, t.window.height, t.window.vsync = 640, 480, 0
  t.modules.audio = false
end
