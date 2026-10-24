package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local rows = dofile(root .. "/tests/rom_text/cases.lua").run(root, backend, version, tonumber(api), format)
print("ROM_TEXT_CONTRACT " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("portable native ROM prose")
