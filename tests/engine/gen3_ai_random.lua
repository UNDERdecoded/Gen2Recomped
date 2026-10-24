package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gen3_ai_random/cases.lua").run("gen2", version)
end
require("tests.modkit").finish("native GBA AI random branches")
