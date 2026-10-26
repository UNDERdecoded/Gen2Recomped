package.path = "./?.lua;./?/init.lua;" .. package.path
local root = assert(arg[1])
local f = dofile(root .. "/tests/catch_nickname/fixture.lua").new(root, arg[2], tonumber(arg[3]), arg[4])
local rows = dofile(root .. "/tests/catch_nickname/cases.lua").run(f)
f.close()
print("CATCH_NICKNAME_CONTRACT_RESULT " .. require("src.link.Json").encode({ rows = rows }))
f.T.finish("portable catch nickname shared contract")
