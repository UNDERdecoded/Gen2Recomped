package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.party_codec").run(".", "gen2", version)
  require("tests.enemy_actions.party_codec_hooks").run(".", "gen2", version)
end
require("tests.modkit").finish("native GBA party codec")
