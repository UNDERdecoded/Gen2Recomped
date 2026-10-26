package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.encore").run(".", "gen2", version)
end
require("tests.modkit").finish("native GBA Encore production, execution and expiry")
