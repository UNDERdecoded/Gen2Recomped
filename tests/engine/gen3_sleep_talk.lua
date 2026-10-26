package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.sleep_talk").run(".", "gen2", version)
  require("tests.enemy_actions.sleep_talk").content(".", "gen2", version)
end
require("tests.modkit").finish("native GBA Sleep Talk selection and execution")
