package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/nature_power.lua").content(".", "gen2", version)
  T.eq(#rows, 3024, "same API-3 registered Nature Power caller exercises every contract case")
  for _, row in ipairs(rows) do
    T.eq(row.events[1].move, "PORTABLE_NATURE", "public registered caller retains its canonical identity")
    if row.case ~= "zero_pp" then
      T.eq(#row.events, 2, "registered caller dispatches one child announcement")
    end
  end
end
T.finish("public API-3 Nature Power content registration and native execution")
