package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = unpack(arg)
local rows = dofile(root .. "/tests/ai_class_content/cases.lua")(root, backend, version, tonumber(api))
print("AI_CLASS_CONTENT " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("portable AI class content")
