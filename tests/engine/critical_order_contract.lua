package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, api in ipairs({ 2, 3 }) do
    dofile("tests/critical_order/cases.lua")(".", "gen2", version, api)
  end
end
require("tests.modkit").finish("native critical/type loader contracts")
