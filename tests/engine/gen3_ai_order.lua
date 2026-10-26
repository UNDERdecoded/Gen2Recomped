package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gen3_ai_order/cases.lua").run(".", version)
  dofile("tests/gen3_ai_order/planning.lua").run(version)
end
require("tests.modkit").finish("native GBA AI order")
