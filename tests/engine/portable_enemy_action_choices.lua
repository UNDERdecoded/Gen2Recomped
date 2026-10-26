package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Cases = require("tests.enemy_actions.cases")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    Cases.run(".", "gen2", version, mode[1], mode[2])
  end
end
T.finish("portable enemy move choices")
