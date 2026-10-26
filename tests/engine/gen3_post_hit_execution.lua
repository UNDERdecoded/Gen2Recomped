package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/enemy_actions/post_hit_items.lua").execution(".", "gen2", version)
end
require("tests.modkit").finish("native GBA post-hit items in actual scripts")
