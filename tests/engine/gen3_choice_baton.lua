package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/enemy_actions/baton_pass.lua").run(".", "gen2", version, { choiceBand = true })
end
require("tests.modkit").finish("native GBA Choice Band real Baton Pass continuations")
