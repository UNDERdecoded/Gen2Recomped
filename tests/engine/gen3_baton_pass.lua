package.path = "./?.lua;./?/init.lua;" .. package.path
for _, v in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.baton_pass").run(".", "gen2", v)
end
require("tests.modkit").finish("native Baton Pass command and continuation")
