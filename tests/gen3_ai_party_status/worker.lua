package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local rows = dofile(root .. "/tests/gen3_ai_party_status/cases.lua").run(backend, version)
print("GEN3_AI_PARTY_STATUS " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native GBA AI party status")
