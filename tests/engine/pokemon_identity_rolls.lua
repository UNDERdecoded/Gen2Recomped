package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local old = V.get()
for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
  for _, version in ipairs(V.ORDER) do
    dofile("tests/pokemon_rolls/cases.lua").run(".", "gen2", version, mode[1], mode[2])
  end
end
V.set(old)
T.finish("native shiny.roll and gender.roll contracts")
