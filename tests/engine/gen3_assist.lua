package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local before = V.get()
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/assist.lua").run(".", "gen2", version)
  T.eq(#rows, 6720, "all native party, rejection, weighting, callback and PP cases execute")
  for _, row in ipairs(rows) do
    T.eq(row.events[1].move, "ASSIST", "selected caller announces its public identity")
    T.eq(row.events[1].called, false, "selected caller is not a called move")
    if row.kind == "zero-caller-pp" then
      T.eq(#row.events, 1, "zero PP cannot admit any child")
      T.eq(#row.draws, 0, "zero PP cannot choose a party move")
    else
      for i = 2, #row.events do
        T.eq(row.events[i].called, true, "party moves announce native provenance")
        T.eq(
          row.events[i].pp,
          row.kind == "pressure" and 8 or 9,
          "Assist spends its own PP before any child event"
        )
      end
    end
  end
end
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  V.set(version)
  T.eq(
    require("src.battle.Gen3Builtins").record("ASSIST_EFFECT", nil),
    nil,
    "other generations gain no GBA Assist binding"
  )
end
V.set(before)
T.finish("native Assist weighted party candidates and execution")
