package.path = "./?.lua;./?/init.lua;" .. package.path
local Fixture = dofile("tests/held_item/fixture.lua")
local Cases = dofile("tests/held_item/scheduling.lua")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    Cases.run(f)
    f.close()
  end
end
require("tests.modkit").finish("native GBA held-item scheduling")
