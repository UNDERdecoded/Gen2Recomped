package.path = "./?.lua;./?/init.lua;" .. package.path
local Fixture = dofile("tests/mod_input/fixture.lua")
local f = Fixture.new(".", "gen2", "red", 3, "unified")
dofile("tests/mod_input/cases.lua").run(f)
f.close()
f.T.finish("portable mod.input")
