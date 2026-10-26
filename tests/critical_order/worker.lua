package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = unpack(arg)
local rows = dofile(root .. "/tests/critical_order/cases.lua")(root, backend, version, tonumber(api))
print("CRITICAL_ORDER " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native critical/type ordering")
