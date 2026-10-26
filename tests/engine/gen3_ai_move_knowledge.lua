package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gen3_ai_move_knowledge/cases.lua").run("gen2", version)
end
dofile("tests/gen3_ai_move_knowledge/controller.lua")
require("tests.modkit").finish("native GBA AI move knowledge")
