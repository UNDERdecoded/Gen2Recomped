package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local f = dofile(root .. "/tests/battle_grid/fixture.lua").new(root, backend, version, api, format)
local rows = dofile(root .. "/tests/battle_grid/cases.lua").run(f)
f.close()
print("BATTLE_GRID_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable battle.move_grid_navigation native contract")
