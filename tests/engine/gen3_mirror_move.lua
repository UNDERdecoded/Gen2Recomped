package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/mirror_move.lua").run(".", "gen2", version)
  T.eq(#rows, 352, "every native received-history command input executes")
  for _, row in ipairs(rows) do
    local actor = row.state[row.actor + 1]
    if row.case == "faint-target" then
      T.eq(actor.hp, 0, "the real second incoming command KOs its recipient")
      T.eq(actor.received, 33, "a KO does not replace earlier successful received history")
      T.eq(actor.pp[1], 10, "a fainted recipient never attempts Mirror Move")
    elseif row.case == "self-target" then
      T.eq(actor.received, 33, "another actor's self-target cannot overwrite this recipient's history")
      local foe = row.state[row.actor % 2 == 0 and row.actor + 2 or row.actor]
      T.eq(foe.last, 10, "the self-targeting actor still records its selected move")
      T.eq(actor.pp[1], 9, "Mirror still spends its own selected PP command")
    end
  end
end
T.finish("native Mirror Move received-history conditions and real action sequences")
