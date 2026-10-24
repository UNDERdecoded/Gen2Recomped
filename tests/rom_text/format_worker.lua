package.path = "./?.lua;./?/init.lua;" .. package.path
local root, version = unpack(arg)
require("src.core.GameVersion").set(version)
local rows = dofile(root .. "/tests/rom_text/format_cases.lua").run()
print("ROM_PROSE_FORMAT " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native prose-format boundary")
