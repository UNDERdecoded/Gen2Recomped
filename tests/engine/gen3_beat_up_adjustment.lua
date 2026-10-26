package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.beat_up").run(".", "gen2", version, false, { adjustment = true })
end
require("tests.modkit").finish("native GBA Beat Up held damage adjustment")
