package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local rows = dofile(root .. "/tests/gen3_ai_random/cases.lua").run(backend, version)
print("GEN3_AI_RANDOM " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native GBA AI random branches")
