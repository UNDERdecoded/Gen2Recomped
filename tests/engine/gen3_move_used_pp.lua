package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/enemy_actions/move_used_pp.lua").run(".", "gen2", version)
end
require("tests.modkit").finish("native GBA move-used event and PP command order")
