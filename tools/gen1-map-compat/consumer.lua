-- Exactly this consumer runs on both hosts, with the mod's old require name.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Version = require("src.core.GameVersion")
local Catalog = require("src.import.gba.map_catalog")
local names = dofile(arg[1] .. "/src/compat/gen1/MapNames.lua")
local editions = {}
for edition in (arg[2] or "firered,leafgreen,emerald,ruby,sapphire"):gmatch("[^,]+") do
  editions[#editions + 1] = edition
end
for _, edition in ipairs(editions) do
  Version.set(edition)
  assert(Version.get() == edition, "host does not support requested edition " .. edition)
  local checks = 0
  local function check(condition)
    checks = checks + 1
    assert(condition, edition .. " identity contract check " .. checks)
  end
  for _, row in ipairs(names[edition]) do
    local group, num, id, pret, constant = unpack(row)
    check(Catalog.mapIdFor(group, num) == id)
    check(Catalog.mapIdFor(tostring(group), tostring(num)) == id)
    check(Catalog.pretToEngine(pret) == id)
    local g, n = Catalog.groupNumFor(id)
    check(g == group and n == num)
    for _, alias in ipairs({ id, pret, group .. ":" .. num, constant }) do
      check(Catalog.isKnown(alias))
      check(Catalog.resolve(alias) == id)
      check(Catalog.slotKeyFor(alias) == (group .. "_" .. num))
    end
    check(Catalog.resolve(group, num) == id)
  end
  check(Catalog.resolve("CUSTOM_MAP") == "CUSTOM_MAP")
  check(Catalog.slotKeyFor("CUSTOM_MAP") == nil)
  check(Catalog.isKnown("CUSTOM_MAP") == false)
  check(Catalog.resolve(false) == nil)
  check(Catalog.pretToEngine("") == nil)
  for _, name in ipairs({ "Route987", "CustomRoom_1F", "Custom-Hall", "Route101_Custom" }) do
    print(edition, "fallback", name, Catalog.pretToEngine(name))
  end
  print(edition, "checks", checks)
end
