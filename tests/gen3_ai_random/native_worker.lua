package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, rom = unpack(arg)
local rows = dofile(root .. "/tests/gen3_ai_random/native_cases.lua").run(backend, rom)
print("GEN3_AI_RANDOM_NATIVE " .. require("src.link.Json").encode(rows))
