function love.conf(t)
	assert(os.getenv("FRAME_PACING_QA_GUARDED") == "1", "use tools/check_frame_pacing.py")
	t.identity = assert(os.getenv("POKEPORT_IDENTITY"))
	t.window.title = "Frame pacing QA"
	t.window.width, t.window.height, t.window.vsync = 320, 180, 1
	t.modules.audio = false
end
