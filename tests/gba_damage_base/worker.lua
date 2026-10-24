package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local rows = dofile(root .. "/tests/gba_damage_base/cases.lua").run(backend, version)
print("GBA_DAMAGE_BASE " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("ordinary GBA base damage")
