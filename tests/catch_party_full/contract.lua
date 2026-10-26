package.path = "./?.lua;./?/init.lua;" .. package.path
local root = assert(arg[1])
local f = dofile(root .. "/tests/catch_party_full/fixture.lua").new(root, arg[2], tonumber(arg[3]), arg[4])
local rows = dofile(root .. "/tests/catch_party_full/cases.lua").run(f)
f.close()
print("CATCH_PARTY_FULL_CONTRACT_RESULT " .. require("src.link.Json").encode({ rows = rows }))
f.T.finish("portable party-full catch shared contract")
