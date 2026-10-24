package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local rows = dofile(root .. "/tests/gen3_ai_taunt/cases.lua").run(backend, version)
print("GEN3_AI_TAUNT " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native GBA AI Taunt predicates")
