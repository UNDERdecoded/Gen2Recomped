package.path = "./?.lua;./?/init.lua;" .. package.path
local root = assert(arg[1])
local f = dofile(root .. "/tests/battle_style/fixture.lua").new(root, arg[2], tonumber(arg[3]), arg[4])
local rows = dofile(root .. "/tests/battle_style/cases.lua").run(f)
f.close()
print("BATTLE_STYLE_CONTRACT_RESULT " .. require("src.link.Json").encode({ rows = rows }))
f.T.finish("portable battle style shared contract")
