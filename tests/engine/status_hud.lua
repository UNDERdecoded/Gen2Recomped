package.path = "./?.lua;./?/init.lua;" .. package.path
local f = dofile("tests/status_hud/fixture.lua").new(".", "gen2", "red", 3, "unified")
dofile("tests/status_hud/cases.lua").run(f)
f.close()
f.T.finish("portable battle.status_hud_visible")
