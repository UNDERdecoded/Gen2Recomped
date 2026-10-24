package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "red", "gold", "silver", "crystal", "firered", "emerald" }) do
  dofile("tests/rom_text/cases.lua").run(".", "gen2", version, 3, "unified")
end
T.finish("portable engine prose and native storage readers")
