package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.lock_on").run(".", "gen2", version)
end
require("tests.modkit").finish("native target-owned Lock-On lifecycle")
