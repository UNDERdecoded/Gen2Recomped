package.path = "./?.lua;./?/init.lua;" .. package.path
local f = dofile("tests/world_talk/fixture.lua").new(".", "gen2", "red", 3, "unified")
dofile("tests/world_talk/cases.lua").run(f)
f.close()
f.T.finish("portable world.talk")
