package.path = "./?.lua;./?/init.lua;" .. package.path
local Fixture = dofile("tests/core_update/fixture.lua")
local f = Fixture.new(".", "gen2", "red", 3, "unified")
dofile("tests/core_update/cases.lua").run(f)
f.close()
f.T.finish("portable core.update")
