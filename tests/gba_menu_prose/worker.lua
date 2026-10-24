package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local rows =
  dofile(root .. "/tests/gba_menu_prose/cases.lua").run(root, backend, version, tonumber(api), format)
print("GBA_MENU_PROSE " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native GBA menu prose")
