package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local Fixture, Cases = dofile("tests/held_content/fixture.lua"), dofile("tests/held_content/cases.lua")
local old = V.get()
for _, version in ipairs(V.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    if V.generation(version) == 2 then
      Cases.run(".", "gen2", version, mode[1], mode[2])
    else
      local f = Fixture.new(".", "gen2", version, mode[1], mode[2], "berry")
      T.eq(f.e.api:supports("content", "held_items"), false, "honest generation-specific held registry")
      local held = f.e.api.content.held_items
      T.eq(held.available, false, "unsupported held accessor is unavailable")
      T.eq(held:get("LEFTOVERS"), nil, "unsupported held accessor returns no records")
      T.eq(held:each()(), nil, "unsupported held accessor is empty")
      held:override("LEFTOVERS", { heldEffect = "HELD_BERRY", heldParameter = 7 })
      T.eq(f.data.items.LEFTOVERS.heldEffect, 3, "unsupported definition never changes native item data")
      T.eq(next(f.result.loader.content.held_items.ops), nil, "unsupported writes add no operations")
      f.close()
    end
  end
end
do
  local f = Fixture.new(".", "gen2", "polishedcrystal", 3, "unified", "noop_modern")
  local hp = f.run("BERRY", 200)
  T.eq(hp, 210, "empty held patch retains native modern berry threshold at half HP")
  f.close()
end
V.set(old)
T.finish("held_items public definitions and native generation boundaries")
