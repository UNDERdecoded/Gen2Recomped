package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/enemy_actions/sleep_talk.lua").run(".", "gen2", version, { choiceBand = true })
end
require("tests.modkit").finish("native GBA Choice Band actual called-move dispatch")
