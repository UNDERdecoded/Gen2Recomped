package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, api in ipairs({ 2, 3 }) do
    dofile("tests/ai_class_content/cases.lua")(".", "gen2", version, api)
  end
end
require("tests.modkit").finish("portable AI class content")
