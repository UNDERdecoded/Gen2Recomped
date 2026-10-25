package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/nature_power.lua").chained(".", "gen2", version)
  T.eq(#rows, 3024, "nested native caller keeps every slot, PP and terrain case")
  for _, row in ipairs(rows) do
    local last = row.state[row.actor + 1].lastMove
    if #row.events == 3 then
      T.eq(row.events[2].move, "NATURE_POWER", "Sleep Talk invokes the native terrain caller")
      T.eq(last, 267, "the inner native caller owns resulting move history")
    elseif #row.events == 2 then
      T.eq(last, 214, "changed learned slots preserve ordinary Sleep Talk ownership")
    else
      T.eq(row.case, "zero_pp", "only zero-PP admission omits every child")
    end
  end
end
T.finish("native Sleep Talk to Nature Power caller chains")
