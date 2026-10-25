package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/assist.lua").content(".", "gen2", version)
  T.eq(#rows, 6840, "same API-3 registered Assist includes registered bench moves")
  for _, row in ipairs(rows) do
    T.eq(row.events[1].move, "PORTABLE_ASSIST", "registered caller retains its public identity")
    if row.case == "custom-bench" and row.kind ~= "zero-caller-pp" and row.kind ~= "parent-bench-change" then
      T.eq(
        row.events[2].move,
        "PORTABLE_STRIKE",
        "custom party move executes through its registered canonical effect"
      )
    end
  end
end
T.finish("API-3 Assist and registered party moves")
