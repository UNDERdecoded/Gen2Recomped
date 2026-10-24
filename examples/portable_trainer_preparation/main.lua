-- A preparation UI may retain continueBattle; next itself stays synchronous.
local mod = ...
local out = mod.exports
out.api, out.mode, out.calls = mod, "defer", 0
out.stop = mod.hooks:wrap("trainer.before_battle", function(next, game, context, continueBattle, ...)
  out.calls = out.calls + 1
  out.game, out.context, out.continue, out.extra = game, context, continueBattle, select("#", ...)
  if out.mode == "error" or out.mode == "after error" then
    if out.mode == "after error" then
      next(game, context, continueBattle)
    end
    error("intentional trainer preparation failure")
  end
  if out.mode == "observe" then
    return next(game, context, continueBattle)
  end
  if out.mode == "immediate" then
    continueBattle(out.options)
  end
  return out.mode == "defer" or out.mode == "immediate"
end)
