package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/enemy_actions/choice_selection.lua").run(".", "gen2", version)
end
require("tests.modkit").finish("native GBA Choice Band AI and manual selection contracts")
