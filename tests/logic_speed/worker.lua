package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local f = dofile(root .. "/tests/logic_speed/fixture.lua").new(root, backend, version, api, format)
local rows = dofile(root .. "/tests/logic_speed/cases.lua").run(f)
f.close()
local bare = dofile(root .. "/tests/logic_speed/fixture.lua").new(root, backend, version, api, format, true)
bare.T.eq(require("src.mods.Runtime").wantsHook("core.logic_speed"), false, "no-mod runtime")
bare.T.eq(bare.game:logicSpeed(), 4, "no-mod native resolver")
bare.close()
print("LOGIC_SPEED_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable core.logic_speed contract")
