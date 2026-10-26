package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local before = V.get()
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/nature_power.lua").run(".", "gen2", version)
  T.eq(#rows, 3024, "all terrain, slot, PP, item and pressure cases execute")
  for _, row in ipairs(rows) do
    if row.case == "zero_pp" then
      T.eq(#row.events, 1, "zero PP announces only the caller")
      T.eq(#row.damage, 0, "zero PP never admits the child")
    else
      T.eq(#row.events, 2, "caller and called child announce exactly once")
      T.eq(row.events[1].called, false, "the selected Nature Power is the caller")
      T.eq(row.events[2].called, true, "the terrain attack is a native child")
      local expected = row.case == "parent_zero" and 0
        or row.case == "parent_replace" and 3
        or row.case == "parent_remove" and "absent"
        or row.case == "parent_reorder" and 4
        or 10
      T.eq(row.events[2].pp, expected, "the child event precedes the selected-slot PP command")
    end
  end
  V.set(version)
  local N = require("src.battle.Gen3NaturePower")
  for name, number in pairs({
    GRASS = 0,
    LONG_GRASS = 1,
    SAND = 2,
    UNDERWATER = 3,
    WATER = 4,
    POND = 5,
    MOUNTAIN = 6,
    CAVE = 7,
    BUILDING = 8,
    PLAIN = 9,
  }) do
    T.eq(
      N.terrain({ gen3Terrain = name, game = {} }),
      number,
      "native cached terrain names retain the GBA identifier"
    )
  end
  T.eq(
    N.terrain({ terrain = "bad", gen3Terrain = "GRASS" }),
    8,
    "explicit invalid terrain retains reference fallback"
  )
  T.eq(N.terrain({ terrain = "4" }), 4, "numeric terrain string is retained")
end
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  V.set(version)
  T.eq(
    require("src.battle.Gen3Builtins").record("NATURE_POWER_EFFECT", nil),
    nil,
    "other generations gain no native Nature Power binding"
  )
end
V.set(before)
T.finish("native Nature Power selection and child PP command")
