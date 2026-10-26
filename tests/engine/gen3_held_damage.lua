package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/held_item/damage.lua").run(".", "gen2", version)
end
require("tests.modkit").finish("native GBA held damage command")
