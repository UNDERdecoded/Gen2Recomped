function love.conf(t)
	assert(os.getenv("DECODED_PROFILE_QA_GUARDED") == "1", "use tools/check_decoded_profiles.py")
	t.identity = assert(os.getenv("POKEPORT_IDENTITY"))
	t.window.title = "Decoded script profile QA"
	t.window.width, t.window.height, t.window.vsync = 320, 180, 1
	t.modules.audio = false
end
