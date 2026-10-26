package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local rows = dofile(root .. "/tests/held_item/damage.lua").run(root, backend, version)
print("HELD_DAMAGE " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native GBA held damage command")
