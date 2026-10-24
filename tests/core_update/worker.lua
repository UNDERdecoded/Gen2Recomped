package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local f = dofile(root .. "/tests/core_update/fixture.lua").new(root, backend, version, api, format)
local rows = dofile(root .. "/tests/core_update/cases.lua").run(f)
f.close()
print("CORE_UPDATE_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable core.update contract")
