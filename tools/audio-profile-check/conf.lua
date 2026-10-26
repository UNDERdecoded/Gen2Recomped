function love.conf(t)
  assert(os.getenv("AUDIO_PROFILE_QA_GUARDED") == "1", "use the guarded audio checker")
  t.identity = assert(os.getenv("POKEPORT_IDENTITY"))
  t.window.title = "Native PCM qualification"
  t.window.width, t.window.height, t.window.vsync = 480, 240, 1
  t.modules.audio = false
end
