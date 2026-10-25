package.path = "./?.lua;./?/init.lua;" .. package.path
local Fixture = dofile("tests/level_visible/fixture.lua")
local f = Fixture.new(".", "gen2", "red", 3, "unified")
-- Public registration is executable proof for the hook coverage audit.
local off = f.exports.api.hooks:wrap("pokemon.level_visible", function(next)
  return next()
end)
dofile("tests/level_visible/cases.lua").run(f)
off()
f.close()
f.T.finish("portable pokemon.level_visible")
