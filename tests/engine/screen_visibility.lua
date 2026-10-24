package.path = "./?.lua;./?/init.lua;" .. package.path
local f = dofile("tests/screen_visibility/fixture.lua").new(".", "gen2", "red", 3, "unified")
dofile("tests/screen_visibility/cases.lua").run(f)
f.close()
f.T.finish("portable screen.render_visible")
