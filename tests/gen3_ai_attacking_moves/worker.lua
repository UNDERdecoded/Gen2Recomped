package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local rows = dofile(root .. "/tests/gen3_ai_attacking_moves/cases.lua").run(root, backend, version)
print("GEN3_AI_ATTACKING_MOVES " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native GBA AI attacking moves")
