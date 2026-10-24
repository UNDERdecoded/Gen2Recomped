package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local old = V.get()
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, api in ipairs({ 2, 3 }) do
    dofile("tests/text_sources/cases.lua").run(".", "gen2", version, api, "unified")
  end
end
V.set(old)
T.finish("portable source text and native script readers")
