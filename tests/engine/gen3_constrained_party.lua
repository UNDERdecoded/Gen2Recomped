package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.constrained_party").run(".", "gen2", version)
end
require("tests.modkit").finish("native Gen-3 constrained party construction")
