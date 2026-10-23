package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local f = dofile(root .. "/tests/input_hooks/fixture.lua").new(root, backend, version, api, format)
local rows = dofile(root .. "/tests/input_hooks/cases.lua").run(f)
f.close()
print("INPUT_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable input contract")
