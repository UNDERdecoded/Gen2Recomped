package.path = "./?.lua;./?/init.lua;" .. package.path
for _, v in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.rage").run(".", "gen2", v)
end
require("tests.modkit").finish("native GBA Rage activation, PP and move-end boosts")
