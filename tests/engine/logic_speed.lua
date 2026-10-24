package.path = "./?.lua;./?/init.lua;" .. package.path
local Fixture = dofile("tests/logic_speed/fixture.lua")
local f = Fixture.new(".", "gen2", "red", 3, "unified")
dofile("tests/logic_speed/cases.lua").run(f)
f.close()
f.T.finish("portable core.logic_speed")
