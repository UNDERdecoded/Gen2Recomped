package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local L = require("src.mods.RomTextLabels")
T.eq(package.loaded["src.mods.rom_text_labels.firered"], nil, "label data loads lazily")
T.eq(L.forVersion("red"), nil, "GB does not inherit a Gen-2/3 prose catalog")
T.eq(L.forVersion("platinum"), nil, "DS has no claimed label catalog")
T.eq(L.forVersion("ruby"), nil, "unregistered host GBA profile has no guessed offsets")
T.eq(L.forVersion("gold")._WokeUpText, true, "Gen-2 prose label is known")
T.eq(L.forVersion("gold")["55:4067"], nil, "VM bank/address is not engine prose")
T.eq(L.forVersion("gold").TEXT_S55_4067, nil, "host physical VM key is not engine prose")
for _, version in ipairs({ "firered", "emerald" }) do
  local facts = dofile("tests/rom_text/labels_" .. version .. ".lua")
  local count = 0
  for label, offset in pairs(facts.text) do
    T.eq(type(label), "string", "semantic storage label is named")
    T.check(type(offset) == "number" and offset > 0, "semantic storage binding has exact native address")
    count = count + 1
  end
  T.eq(count, 10, "all five storage actions and descriptions have provenance")
  T.eq(next(facts.battle), nil, "storage actions are ordinary text, not battle-code strings")
end
T.eq(L.forVersion("gold"), L.forVersion("gold"), "native Gen-2 label dictionary is cached")
T.finish("native prose-label provenance facts")
