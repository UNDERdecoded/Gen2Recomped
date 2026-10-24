package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gba_menu_prose/cases.lua").run(".", "gen2", version, 3, "unified")
end
T.finish("native GBA menu-prose bindings")
