package.path = "./?.lua;./?/init.lua;" .. package.path
local f = dofile("tests/battle_bottom_ui/fixture.lua").new(".", "gen2", "red", 3, "unified")
dofile("tests/battle_bottom_ui/cases.lua").run(f)
f.close()
f.T.finish("portable battle.bottom_ui_visible")
