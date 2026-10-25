package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.multi_hit").run(".", "gen2", version)
end
require("tests.modkit").finish("native ordinary GBA multi-hit execution")
