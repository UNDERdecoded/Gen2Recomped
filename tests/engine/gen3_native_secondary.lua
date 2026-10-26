package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  for _, execution in ipairs({ false, true }) do
    require("tests.enemy_actions.secondary").run(".", "gen2", version, execution)
  end
end
require("tests.modkit").finish("native GBA secondary chance and effect boundaries")
