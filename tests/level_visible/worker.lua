package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local fixture = dofile(root .. "/tests/level_visible/fixture.lua")
local f = fixture.new(root, backend, version, api, format)
local rows = {
  native = dofile(root .. "/tests/level_visible/native.lua").run(f),
  predicate = dofile(root .. "/tests/level_visible/cases.lua").run(f),
}
f.close()
local bare = fixture.new(root, backend, version, api, format, true)
bare.T.eq(require("src.mods.Runtime").wantsHook("pokemon.level_visible"), false, "bare Runtime")
bare.T.eq(bare.visible("party"), true, "no-mod default")
bare.close()
print("LEVEL_VISIBLE_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable pokemon.level_visible")
