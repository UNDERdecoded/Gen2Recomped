package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/assist.lua").failedCallers(".", "gen2", version)
  T.eq(#rows, 36, "all positions and previous histories execute failed native children")
  for _, row in ipairs(rows) do
    T.eq(row.last, row.previous, "failed child preserves previous native move history")
    T.eq(row.pp, 9, "only the selected outer Metronome spends PP")
    T.eq(#row.events, 2, "both actual caller announcements remain public")
    T.eq(row.events[1].move, "METRONOME", "outer announcement remains native")
    T.eq(
      row.events[2].move,
      row.child == 274 and "ASSIST" or "MIRROR_MOVE",
      "selected failed child announces"
    )
    T.eq(#row.damage, 0, "failed child does no damage")
  end
end
T.finish("native failed Assist and Mirror Move preserve caller history")
