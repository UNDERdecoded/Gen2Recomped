package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.spit_up").run(".", "gen2", version)
end
require("tests.modkit").finish("native GBA Spit Up")
