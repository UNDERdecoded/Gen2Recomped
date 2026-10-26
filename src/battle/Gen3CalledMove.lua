-- Shared native called-move targeting and provenance. A caller may lend its
-- selected PP slot to the first child body; ordinary calls lend no PP.
local C = {}
function C.call(ctx, pick, ppSlot)
  local b, user = ctx.battle, ctx.user
  local move = ctx.data.moves[pick]
  if not move then
    return
  end
  local targets
  if b:isDouble() and tonumber(move.target) == 32 then
    -- The native all-other-battlers script uses controller slot order,
    -- independent of speed and the generic foes-then-ally convenience list.
    targets = {}
    local order = b.linkRole == "guest" and { 1, 0, 3, 2 } or { 0, 1, 2, 3 }
    for _, id in ipairs(order) do
      local target = b:battlerAt(id)
      if target and target ~= user and target.mon.hp > 0 then
        targets[#targets + 1] = target
      end
    end
  elseif b:isDouble() then
    targets = require("src.battle.Gen3Encore").targets(b, user, move)
  else
    targets = { tonumber(move.target) == 16 and user or b:defaultTargetFor(user) }
  end
  local chained = false
  for i, target in ipairs(targets) do
    chained = require("src.battle.Gen3ChoiceBand").call(
      ctx,
      pick,
      target,
      i > 1,
      i > 1,
      i == 1 and ppSlot or nil
    ) or chained
  end
  -- A nested native caller owns the resulting history; an ordinary child
  -- records this caller, including the existing switch/resume behavior.
  if not chained then
    user.lastMove = ctx.move.id
  end
end
return C
