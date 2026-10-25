package.path = "./?.lua;./?/init.lua;" .. package.path
local root, version = unpack(arg)
local rows = dofile(root .. "/tests/gen3_ai_order/cases.lua").run(root, version)
print("GEN3_AI_ORDER " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native GBA AI order")
